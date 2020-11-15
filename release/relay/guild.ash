// This script is loosely based on the Improved Guild Trainer by rbond86.
// For their work, see:
// - Original thread: https://kolmafia.us/threads/improved-guild-trainer.13972/
// - Repository: https://sourceforge.net/projects/rlbond86-mafia-scripts/

script "BetterTrainer";
notify "philmasterplus";

import <BetterTrainer/XPathMatch.ash>


boolean __DEBUG__ = true;

// Returns the current (system) time down to milliseconds. Used for debug messages.
string _debug_time() {
  return now_to_string("HH:mm:ss.SSS z");
}

// Prints a debug message to the CLI
void _debug(string msg) {
  if (__DEBUG__) print(`[relay/guild.ash][{_debug_time()}] {msg}`);
}

// Prints a debug message to the CLI and aborts the script
void _error(string msg) {
  abort(`[relay/guild.ash][{_debug_time()}] ERROR: {msg}`);
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
  skill the_skill = to_skill(skill_name);
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

  // Check for the existence of a <form>, and use it to determine whether a
  // skill can be purchased. We could check the character level ourselves, but
  // it might break if the way skills are unlocked changes in the future
  // (possibly in some challenge path)
  XPathMatch form = row_node.find("//form");
  string form_attributes;
  // If the form does not exist, leave the attributes empty
  if (!form.empty()) {
    matcher form_attr_matcher = create_matcher("<form([\\s\\S]*?)>", form.raw());
    if (!form_attr_matcher.find()) {
      _error(`Cannot extract form attributes from: {form.raw()}`);
    }
    form_attributes = form_attr_matcher.group(1);
  }

  // Save the hidden inputs and reuse them later in our new skill table
  string [int] hidden_inputs = row_node.find("//input[@type='hidden']").nodes;
  return new TrainerSkillInfo(
    the_skill, node_img, node_skill_name.raw(), form_attributes, hidden_inputs
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


// Utility function. Replaces the first occurrence of `find` with `replaced`.
string replace_once(string text, string find, string replaced) {
  int index = text.index_of(find);
  return text.substring(0, index) + replaced + text.substring(index + find.length());
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

  string [skill] permed_skills;

  skill current_skill = $skill[ none ];
  // This XPath selector neatly splits the contents of all table cells, such
  // that the tokens look like:
  //
  //    "Unpermed skill name", "", "Permed skill name", "HP", "", ...
  //
  // We will iterate through each and build a map of permed skills.
  foreach _, skill_name_or_perm_status in xpath(skill_table, "//td/*/text()") {
    if (skill_name_or_perm_status == "") {
      // Ignore blank cells
      continue;
    } else if (skill_name_or_perm_status == "P" || skill_name_or_perm_status == "HP") {
      string perm_status = skill_name_or_perm_status;

      if (current_skill == $skill[ none ]) {
        _debug(`parse_permed_skills(): Unpaired perm status token found ("{perm_status}"). This will be ignored.`);
      } else {
        permed_skills[current_skill] = perm_status;
        // Reset the current skill
        current_skill = $skill[ none ];
      }
    } else {
      string skill_name = skill_name_or_perm_status;
      current_skill = to_skill(skill_name);
      if (current_skill == $skill[ none ]) {
        _error(`parse_permed_skills(): Unrecognized skill name: {skill_name}`);
      }
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
    return `<div style="font-size: 50%; color: #009900">Softcore permed skill</div>`;
  } else if (perm_status == "HP") {
    return `<div style="font-size: 50%; color: #0000cc">Hardcore permed skill</div>`;
  }

  _error(`make_perm_info_blurb(): Unexpected perm status: {perm_status}`);
  return "NOT_REACHED"; // Dummy return statement
}


// Generates the HTML markup of the better skill table for the current
// character's class.
string generate_skill_table(
  TrainerSkillInfo [skill] trainable_skills, string [skill] perm_info
) {
  skill [int][int] guild_skills = class_guild_skills(my_class());

  buffer html;
  html.append("<table>");
  html.append("<tbody>");

  foreach level in guild_skills {
    html.append("<tr>");
    html.append(`  <td class="small" style="text-align: right; padding-right: .5em">Level {level})</td>`);

    foreach _, sk in guild_skills[level] {
      string perm_info_blurb = make_perm_info_blurb(perm_info[sk]);
      string BUTTON_DISABLED_STYLE = "color: #cccccc; border-color: #cccccc;";

      if (trainable_skills contains sk) {
        // Good, the skill is either buyable or unlockable.
        TrainerSkillInfo skill_info = trainable_skills[sk];

        html.append(`<td><span style="cursor: pointer">{skill_info.node_img}</span></td>`);
        html.append(`<td><b style="cursor: pointer">{skill_info.node_skill_name}</b>{perm_info_blurb}</td>`);
        html.append(`<td>`);
        html.append(`  <form {skill_info.form_attributes} style="margin: 0">`);
        if (skill_info.form_attributes.length() > 0) {
          // The form action exists, and the button is usable
          html.append(`    <button class="button" type="submit" style="min-width: 5.5em">`);
        } else {
          // Skill cannot be purchased because your level is too low.
          // The form action does not exist, and the button is unusable
          html.append(`    <button class="button" type="submit" disabled style="min-width: 5.5em; {BUTTON_DISABLED_STYLE}">`);
        }
        html.append(`      Buy<br><span style="font-size: 75%; pointer-events: none">{to_string(sk.traincost, "%,d")} meat</span>`);
        html.append(`    </button>`);
        html.append(`    {"".join(skill_info.hidden_inputs)}`);
        html.append(`  </form>`);
        html.append(`</td>`);
      } else {
        // The vanilla trainer page does NOT provide link and images
        // Thus, we have to generate our own links
        // (This may break if KoL changes the guild trainer in the future)
        string onclick = `poop('desc_skill.php?whichskill={to_int(sk)}&self=true', 'skill', 350, 300)`;
        html.append(`<td><img src="/images/itemimages/{sk.image}" onclick="{onclick}" style="cursor: pointer"></td>`);
        html.append(`<td><b onclick="{onclick}" style="cursor: pointer">{sk}</b>{perm_info_blurb}</td>`);
        html.append(`<td>`);
        if (have_skill(sk)) {
          // You already bought or permed the skill
          html.append(`  <div style="text-align: center; color: #00cc00; font-weight: bold: font-size: 300%">&#x2714;</div>`);
        } else {
          // The guild store doesn't display the skill for unknown reason
          html.append(`  <button class="button" type="submit" disabled style="min-width: 5.5em; {BUTTON_DISABLED_STYLE}">N/A</button>`);
        }
        html.append(`</td>`);
      }
    }

    html.append("</tr>");
  }

  html.append("</tbody>");
  html.append("</table>");

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

  // Write everything before the original table
  write(page.substring(0, vanilla_skill_table_start));

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
