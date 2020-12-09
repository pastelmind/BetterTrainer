// This script is loosely based on the Improved Guild Trainer by rbond86.
// For their work, see:
// - Original thread: https://kolmafia.us/threads/improved-guild-trainer.13972/
// - Repository: https://sourceforge.net/projects/rlbond86-mafia-scripts/

script "BetterTrainer";
notify "philmasterplus";
since 20.7;

import <BetterTrainer/BetterTrainer-common.ash>
import <BetterTrainer/XPathMatch.ash>


_set_current_file("relay/guild.ash");


// @internal
// Returns a character version of the given entity token.
string _entity_code_to_char(string entity_code) {
  switch (entity_code) {
      case "quot":
      case "#34":
        return '"';
      case "apos":
      case "#39":
        return "'";
  }
  _error(`Unknown HTML entity code: &{entity_code};`);
  return "NOT_REACHED"; // Dummy return statement
}


matcher _ENTITY_MATCHER = create_matcher("&(\\w+|#\\d+);", "");

// Utility function
// Replace some offending HTML entities in skill names with proper characters
string _unescape_entities(string escaped) {
  buffer unescaped;

  _ENTITY_MATCHER.reset(escaped);
  while (_ENTITY_MATCHER.find()) {
    string entity_code = _ENTITY_MATCHER.group(1);
    _ENTITY_MATCHER.append_replacement(unescaped, _entity_code_to_char(entity_code));
  }
  _ENTITY_MATCHER.append_tail(unescaped);

  return unescaped;
}


// Retrieves the guild skill data for the given class.
// The returned mapping contains an array of skills for each level.
// This uses KoLmafia's internal data.
skill [int][int] class_guild_skills(class the_class) {
  skill [int][int] guild_skills;

  foreach sk in $skills[] {
    // All skills have a level between -1 and 15, inclusive.
    // -1 means the skill does not have a level, and is not a guild skill.
    // 0 means the skill is a starting skill, and therefore not a guild skill.
    // 1~15 means the skill is a guild skill.
    if (sk.class == the_class && sk.level > 0) {
      // Sanity check, probably unnecessary
      if (sk.traincost <= 0) {
        _debug(`{sk} appears to be a guild skill, but does not have an associated training cost.`);
      }

      guild_skills[sk.level][guild_skills[sk.level].count()] = sk;
    }
  }

  return guild_skills;
}


// Represents a purchaseable skill info
record TrainerSkillInfo {
  skill sk;
  // Skill icon node (<img> element)
  string node_img;
  // Skill name node (<a> element)
  string node_skill_name;
  // Whether the Train button is enabled
  boolean is_enabled;
  // Attributes of the associated <form> element
  string form_attributes;
  // Any associated <input type="hidden"> elements
  string [int] hidden_inputs;
};


// Extracts a trainer skill info record by parsing a <tr> node.
TrainerSkillInfo parse_info_from_row(XPathMatch row_node) {
  // Identify the skill by name
  XPathMatch node_skill_name = row_node.find("//a").first();
  string skill_name = node_skill_name.find("/text()").raw();

  // Some skills have "&apos;" and possibly other HTML entities in the HTML.
  // We should unescape them first
  skill the_skill = to_skill(_unescape_entities(skill_name));
  if (the_skill == $skill[ none ]) {
    _error(`KoLmafia doesn't know about the skill "{skill_name}"`);
  }

  // Verify that the skill level in the text matches the known skill level
  string LEVEL_PATTERN = "Level (\\d+)";
  string level_text = row_node.find("//td").matching(LEVEL_PATTERN).last().raw();

  matcher m = create_matcher(LEVEL_PATTERN, level_text);
  if (!m.find()) {
    _error(`This should be unreachable. Cannot find "{LEVEL_PATTERN}" although it was already matched.`);
  }
  int level_from_text = to_int(m.group(1));
  if (the_skill.level != level_from_text) {
    _debug(`KoLmafia believes that {the_skill} has a level of {the_skill.level}, but the game says that it's actually {level_from_text}`);
  }

  // Build the skill info record
  string node_img = row_node.find("//img").raw();

  boolean is_enabled = false;
  string form_attributes;
  string [int] hidden_inputs;

  // Check for the existence of a <form>, and use it to determine whether a
  // skill can be purchased. We could check the character level ourselves, but
  // it might break if the way skills are unlocked changes in the future
  // (possibly in some challenge path)
  XPathMatch form = row_node.find("//form");
  // If the form exists, it means the skill can be purchased now
  if (!form.empty()) {
    matcher form_attr_matcher = create_matcher("<form([\\s\\S]*?)>", form.raw());
    if (!form_attr_matcher.find()) {
      _error(`Cannot extract form attributes from: {form.raw()}`);
    }

    is_enabled = true;
    form_attributes = form_attr_matcher.group(1);
    // Save the hidden inputs and reuse them later in our new skill table
    hidden_inputs = row_node.find("//input[@type='hidden']").nodes;
  }

  return new TrainerSkillInfo(
    the_skill,
    node_img,
    node_skill_name.raw(),
    is_enabled,
    form_attributes,
    hidden_inputs
  );
}


// Parse the vanilla guild trainer skill table and extract skill information.
TrainerSkillInfo [skill] parse_trainer_skills(string skill_table) {
  TrainerSkillInfo [skill] trainer_skills;
  foreach _, table_row in xpath_match(skill_table, "//tr").items() {
    TrainerSkillInfo skill_info = parse_info_from_row(table_row);
    trainer_skills[skill_info.sk] = skill_info;
  }
  return trainer_skills;
}


// Utility function
string join(string joiner, string [int] fragments) {
  buffer joined;
  boolean is_first = true;
  foreach _, str in fragments {
    if (is_first) {
      is_first = false;
    } else {
      joined.append(joiner);
    }
    joined.append(str);
  }
  return joined;
}


// Utility function
// Uses XPath to strip all HTML tags from the markup, leaving only text
string _xpath_strip_html(string markup) {
  return xpath(markup, "text()")[0];
}


// Parses the contents of charsheet.php and extracts your permed skills.
// Value of "P" means the skill is (softcore) permanent.
// Value of "HP" means the skill is hardcore permanent.
// A value not in the map means the skill is not permed.
string [skill] parse_permed_skills(string charsheet) {
  // Extract the first <table> after the text "Skills:"
  matcher skill_table_matcher = create_matcher(
    "Skills:[\\s\\S]*?(<table[\\s\\S]*?</table>)", charsheet
  );
  if (!skill_table_matcher.find()) {
    _error("parse_permed_skills(): Cannot match the skill table. Update the script or ask the author for more info.");
  }
  string skill_table = skill_table_matcher.group(1);

  // Since we're already using a regular expression to match the cell AND extract
  // its cell contents, we don't need to use xpath() here.
  // Note: We can't use the "one or more" quantifier (+) to exclude empty cells
  // here, because regex is dumb and tries to parse two cells as a single cell.
  //
  //    <td></td><td></td>    --> If we use "+" quantifier, the regex will parse
  //                              this as <td> ( </td><td> ) </td>!!
  matcher table_cell_matcher = create_matcher(
    "<td[^>]*>([\\s\\S]*?)</td>", skill_table
  );
  matcher perm_status_matcher = create_matcher("\\s*\\((P|HP)\\)$", "");

  string [skill] permed_skills;
  while (table_cell_matcher.find()) {
    string cell_content = table_cell_matcher.group(1);

    // Some table rows are empty, while others contain help text
    // We are mainly interested in cells that contain a list of skill names,
    // each name followed by (P) or (HP) and separated by <br>.
    foreach _, token in cell_content.split_string("<br>") {
      // Strip all tags from the markup
      string text = _xpath_strip_html(token);

      // Ignore empty text and blurbs
      if (
        text == ""
        || text.contains_text("show permanent skills you can't use right now")
        || text.contains_text("(P) = Permanent skill")
        || text.contains_text("(HP) = Hardcore Permanent skill")
      ) {
        continue;
      }

      // If the text doesn't have the skill perm status, ignore it
      if (!perm_status_matcher.reset(text).find()) continue;

      string perm_status = perm_status_matcher.group(1);
      string skill_name = perm_status_matcher.replace_first("");
      skill sk = to_skill(skill_name);
      if (sk == $skill[ none ]) {
        _error(`parse_permed_skills(): Unrecognized skill name: {skill_name}`);
      }

      permed_skills[sk] = perm_status;
    }
  }

  return permed_skills;
}


// If the skill is permed, generate a HTML fragment containing the perm info blurb.
// Otherwise, return an empty string.
string make_perm_info_blurb(string perm_status) {
  // Note: Use a <div> to put the blurb on a separate line under the skill name.
  if (perm_status == "") {
    return "";
  } else if (perm_status == "P") {
    return `<div class="better-trainer-skill-table__perm-info better-trainer-skill-table__perm-info--sc">Softcore permed skill</div>`;
  } else if (perm_status == "HP") {
    return `<div class="better-trainer-skill-table__perm-info better-trainer-skill-table__perm-info--hc">Hardcore permed skill</div>`;
  }

  _error(`make_perm_info_blurb(): Unexpected perm status: {perm_status}`);
  return "NOT_REACHED"; // Dummy return statement
}


// Generate the markup for the Train <button>
string generate_button(skill sk, boolean is_available, boolean is_enabled) {
  buffer button;

  string disabled_attr = is_enabled ? "" : "disabled";
  string button_classes = "button better-trainer-guild-table__unlock-button";
  if (!is_enabled) {
    button_classes += " better-trainer-guild-table__unlock-button--disabled";
  }
  // Reduce line-height to make the button vertically compact in HTML standards mode
  button.appendln(`      <button class="{button_classes}" type="submit" {disabled_attr}>`);

  if (is_available) {
    // Skill can be (eventually) purchased
    button.appendln(`        Train<br>`);

    string meat_cost_classes = "better-trainer-guild-table__meat-cost";
    if (my_meat() < sk.traincost) {
      meat_cost_classes += ` better-trainer-guild-table__meat-cost--unaffordable`;
    }
    if (!is_enabled) {
      meat_cost_classes += ` better-trainer-guild-table__meat-cost--disabled`;
    }
    // pointer-events: none is needed to prevent the mousedown handler from triggering
    button.appendln(`        <span class="{meat_cost_classes}">{to_string(sk.traincost, "%,d")} meat</span>`);
  } else {
    // The guild store doesn't display the skill for unknown reason
    button.appendln(`        N/A`);
  }

  button.append(`      </button>`);

  return button;
}


// Generates the HTML markup of the better skill table for the current
// character's class.
string generate_skill_table(
  TrainerSkillInfo [skill] trainable_skills, string [skill] perm_info
) {
  skill [int][int] guild_skills = class_guild_skills(my_class());

  buffer html;
  html.appendln('<div class="better-trainer-guild-table">');

  int row_num = 0;
  foreach level in guild_skills {
    ++row_num;
    html.appendln(`  <div class="better-trainer-guild-table__level" style="grid-row: {row_num}">Level {level})</div>`);

    foreach _, sk in guild_skills[level] {
      // Generate clickable icon and skill name links
      // Note: We choose to always write our own onclick handler instead of
      // trying to reuse the KoL's onclick handler.
      // If KoL's code ever changes, it's better for our table to break and
      // behave consistently, rather than behave correctly for some cells and
      // break for other cells.
      // Also, we have a "show original skill table" link just in case.
      string skillDescUrl = `desc_skill.php?whichskill={to_int(sk)}&self=true`;
      string onclick = `poop('{skillDescUrl}', 'skill', 350, 300)`;
      string skll_name_classes = "better-trainer-guild-table__skill-name";
      if (trainable_skills contains sk && !trainable_skills[sk].is_enabled) {
        skll_name_classes += " better-trainer-guild-table__skill-name--disabled";
      }
      html.appendln(`  <div class="better-trainer-guild-table__skill-cell better-trainer-skill-tooltip" style="grid-row: {row_num}" onclick="{onclick}" data-better-trainer-desc-url="{skillDescUrl}">`);
      html.appendln(`    <img class="better-trainer-guild-table__icon" src="/images/itemimages/{sk.image}">`);
      html.appendln(`    <div class="better-trainer-guild-table__skill-content">`);
      html.appendln(`      <span class="{skll_name_classes}">{sk.name}</span>`);
      string perm_info_blurb = make_perm_info_blurb(perm_info[sk]);
      if (perm_info_blurb != "") {
        html.appendln(`      {perm_info_blurb}`);
      }
      html.appendln(`    </div>`);
      html.appendln(`  </div>`);

      // Generate Train button or checkmark
      html.appendln(`  <div class="better-trainer-guild-table__control-cell" style="grid-row: {row_num}">`);
      if (trainable_skills contains sk) {
        // Good, the skill is either buyable or unlockable.
        TrainerSkillInfo skill_info = trainable_skills[sk];
        html.appendln(`    <form {skill_info.form_attributes}>`);
        html.appendln(generate_button(sk, true, skill_info.is_enabled));
        html.appendln(`      {"".join(skill_info.hidden_inputs)}`);
        html.appendln(`    </form>`);
      } else {
        if (have_skill(sk)) {
          // You already bought or permed the skill
          html.appendln(`    <div class="better-trainer-guild-table__status better-trainer-guild-table__status--owned" title="You already learned this skill">&#x2714;</div>`);
        } else {
          // The guild store doesn't display the skill for unknown reason
          html.appendln(generate_button(sk, false, false));
        }
      }
      html.appendln(`  </div>`);
    }
  }

  html.appendln("</div>");
  return html;
}


void main() {
  _debug("Loaded");

  // Check if the user is visiting the guild trainer (guild.php?place=trainer)
  // or has just bought a skill (guild.php?action=buyskill)
  if (form_field("place") != "trainer" && form_field("action") != "buyskill") {
    // Do nothing. This causes KoLmafia to present the original page as-is.
    return;
  }

  _debug("Detected Guild Trainer page");
  buffer page = visit_url();

  _debug("Parsing offered guild trainer skills...");

  // Locate the skill table, which is below the "Available skills" text
  // Note: We choose not to use xpath() to extract the outer skill table,
  // because it tries to "clean" bad HTML markup and modifies it. It would
  // prevent us from selectively replacing parts of the page.
  matcher skill_table_matcher = create_matcher(
    "Available skills:[\\s\\S]*?(<table[\\s\\S]*?</table>)", page
  );
  if (!skill_table_matcher.find()) {
    _error("Cannot find the skill table");
  }
  string vanilla_skill_table = skill_table_matcher.group(1);
  int vanilla_skill_table_start = skill_table_matcher.start(1);
  int vanilla_skill_table_end = skill_table_matcher.end(1);

  // Iterate through the <tr>s of the *inner* <table>
  // and construct a map of trainable skills
  TrainerSkillInfo [skill] trainable_skills = parse_trainer_skills(vanilla_skill_table);

  _debug("Retrieving permed skills...");

  string charsheet = visit_url("charsheet.php");
  string [skill] perm_info = parse_permed_skills(charsheet);

  _debug("Generating improved Guild Trainer page...");

  // To use Tippy (and Popper) we need HTML standards mode.
  // Unfortunately, KoL does not generate a <!DOCTYPE html> as of 2020-11-21.
  // Forcing us to inject it manually.
  if (!page.contains_text("<!DOCTYPE")) {
    writeln("<!DOCTYPE html>");
  }

  _debug("Injecting custom JS and CSS...");
  matcher closing_head_tag_matcher = create_matcher("</head>", page);
  if (!closing_head_tag_matcher.find()) {
    _error("Cannot find the closing </head> tag");
  }

  // Write everything before the closing </head> tag
  // before the original table
  write(page.substring(0, closing_head_tag_matcher.start()));
  write(generate_tooltip_head_tags());

  // Write the closing </head> tag and everything after it up to the original
  // skill table
  write(page.substring(closing_head_tag_matcher.start(), vanilla_skill_table_start));

  // Insert our pretty table
  write(generate_skill_table(trainable_skills, perm_info));

  // Write a <hr> to separate the new table from the old one
  write("<hr>");

  // Wrap the original table inside a <details>
  write("<details>");
  write('  <summary style="cursor: pointer"><small><u>Click to view/hide the original skill table</u></small></summary>');
  // Write the original table
  write(vanilla_skill_table);
  write("</details>");

  // Write everything after the original table
  write(page.substring(vanilla_skill_table_end));

  _debug("Finished generating page.");
}
