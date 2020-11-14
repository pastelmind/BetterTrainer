// This script is loosely based on the Improved Guild Trainer by rbond86.
// For their work, see:
// - Original thread: https://kolmafia.us/threads/improved-guild-trainer.13972/
// - Repository: https://sourceforge.net/projects/rlbond86-mafia-scripts/

script "BetterTrainer";

import <BetterTrainer/XPathMatch.ash>


boolean __DEBUG__ = true;

// Prints a debug message to the CLI
void _debug(string msg) {
  if (__DEBUG__) print(`[relay/guild.ash][{time_to_string()}] {msg}`);
}

// Prints a debug message to the CLI and aborts the script
void _error(string msg) {
  abort(`[relay/guild.ash][{time_to_string()}] ERROR: {msg}`);
}


// Represents a purchaseable skill info
record TrainerSkillInfo {
  skill sk;
  // Skill icon node (<img> element)
  string node_img;
  // Skill name node (<a> element)
  string node_skill_name;
  // action of the associated <form> element
  string form_action;
  // Any associated <input type="hidden"> elements
  string [int] hidden_inputs;
};


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
      print(`Considering {sk}`);
      // Sanity check, probably unnecessary
      if (sk.traincost <= 0) {
        _debug(`{sk} appears to be a guild skill, but does not have an associated training cost.`);
      }

      guild_skills[sk.level][guild_skills[sk.level].count()] = sk;
    }
  }

  return guild_skills;
}


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
  XPathMatch form = row_node.find("//form");
  string form_action;
  // If the form does not exist, leave the action empty
  if (!form.empty()) form_action = form.find("/@action").raw();
  string [int] hidden_inputs = row_node.find("//input[@type='hidden']").nodes;
  return new TrainerSkillInfo(
    the_skill, node_img, node_skill_name.raw(), form_action, hidden_inputs
  );
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


// Generates the HTML markup of the better skill table for the current
// character's class.
string generate_skill_table(TrainerSkillInfo [skill] trainable_skills) {
  skill [int][int] guild_skills = class_guild_skills(my_class());

  buffer html;
  html.append("<table>");
  html.append("<tbody>");

  foreach level in guild_skills {
    html.append("<tr>");
    html.append(`  <td class="small" style="text-align: right; padding-right: .5em">Level {level})</td>`);

    foreach _, sk in guild_skills[level] {
      if (trainable_skills contains sk) {
        // Good, the skill is either buyable or unlockable.
        TrainerSkillInfo skill_info = trainable_skills[sk];

        html.append(`<td><span style="cursor: pointer">{skill_info.node_img}</span></td>`);
        html.append(`<td><b style="cursor: pointer">{skill_info.node_skill_name}</b></td>`);
        html.append(`<td>`);
        html.append(`  <form action="{skill_info.form_action}" style="margin: 0">`);
        if (skill_info.form_action.length() > 0) {
          // The form action exists, and the button is usable
          html.append(`    <button class="button" type="submit" style="min-width: 5.5em">`);
        } else {
          // Skill cannot be purchased because your level is too low.
          // The form action does not exist, and the button is unusable
          html.append(`    <button class="button" type="submit" disabled style="min-width: 5.5em; color: #cccccc">`);
        }
        html.append(`      Buy<br><span style="font-size: 75%">{to_string(sk.traincost, "%,d")} meat</span>`);
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
        html.append(`<td><b onclick="{onclick}" style="cursor: pointer">{sk}</b></td>`);
        html.append(`<td>`);
        if (have_skill(sk)) {
          // You already bought or permed the skill
          html.append(`  <div style="text-align: center; color: #00cc00; font-weight: bold: font-size: 300%">&#x2714;</div>`);
        } else {
          // The guild store doesn't display the skill for unknown reason
          html.append(`  <button class="button" type="submit" disabled style="min-width: 5.5em; color: #cccccc">N/A</button>`);
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

  // The idea:
  // 1. Iterate through all skill buttons and icons to extract the list of skills (and their guild cost)
  // First, select the table

  // Note: As of r20499, xpath() is VERY VERY limited.
  // It does not support most XPath functions and axes.
  // Thus, we have to manually identify the index of the node that contains the
  // substring we're looking for.

  // Find a <table> that contains the "Available skills" text.
  XPathMatch outer_table = xpath_match(page, "//table").containing("Available skills").last();
  // Find the inner <table> that contains the actual skill icons and buttons.
  XPathMatch vanilla_skill_table = outer_table.find("//table");

  // Iterate through the <tr>s of the *inner* <table> inside the outer <table>
  // and construct a map of trainable skills
  TrainerSkillInfo [skill] trainable_skills;
  foreach _, table_row in vanilla_skill_table.find("//tr").items() {
    print(`tr index: {_}`);
    TrainerSkillInfo skill_info = parse_info_from_row(table_row);
    trainable_skills[skill_info.sk] = skill_info;
  }

  // For each available skill, we need to find several things:
  // - Skill name and icon
  // - Skill level
  // - Skill meat cost
  // - Whether the skill can be bought or not
  //   (Comparing the character level ourselves might break the script, if the
  //    way skills are unlocked changes in some challenge path)
  // - Skill ID sent to server when the "Buy" button is clicked.
  //   This is DIFFERENT from the actual skill ID!

  // To replace the original table, we must find the index of the cleaned HTML:
  string cleaned_html = xpath_clean_html(page);
  int vanilla_skill_table_pos = cleaned_html.index_of(vanilla_skill_table.raw());

  // Write everything before the original table
  write(cleaned_html.substring(0, vanilla_skill_table_pos));

  // Insert our pretty table
  write(generate_skill_table(trainable_skills));

  // Write a <hr> to separate the new table from the old one
  write("<hr>");

  // Wrap the original table inside a <details>
  write("<details>");
  write('  <summary style="cursor: pointer"><small><u>Click to view/hide the original skill table</u></small></summary>');
  // Write the original table
  write(vanilla_skill_table.raw());
  write("</details>");

  // Write everything after the original table
  write(cleaned_html.substring(vanilla_skill_table_pos + vanilla_skill_table.raw().length()));

  // TODO: When the script fails for some reason, we should write a message so that the user knows about it.
}
