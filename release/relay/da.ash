/**
 * BetterTrainer's relay override for the Dungeoneer's Association.
 * This module empowers Avatar of Boris's skill tree.
 */

script "BetterTrainer/dungeons";
since 20.7;

import <BetterTrainer/BetterTrainer-common.ash>


_set_current_file("relay/da.ash");


// Maintain a list of skills in each tree, represented by the skill tree code.
// This is needed because KoLmafia does not know which tree each skill belongs
// in.
boolean [int, skill] AOB_SKILLS = {
  1: $skills[
    Cleave,
    [11002]Ferocity,
    Broadside,
    Sick Pythons,
    Pep Talk,
    Throw Trusty,
    Legendary Luck,
    Song of Cockiness,
    Legendary Impatience,
    Bifurcating Blow,
  ],
  2: $skills[
    Intimidating Bellow,
    Legendary Bravado,
    Song of Accompaniment,
    Big Lungs,
    Song of Solitude,
    Good Singing Voice,
    Song of Fortune,
    Louder Bellows,
    Song of Battle,
    Banishing Shout,
  ],
  3: $skills[
    Demand Sandwich,
    Legendary Girth,
    Song of the Glorious Lunch,
    Big Boned,
    Legendary Appetite,
    Heroic Belch,
    Hungry Eyes,
    More to Love,
    Barrel Chested,
    Gourmand,
  ],
};

string [int] SKILL_TREE_NAMES = {
  1: "Fighting",
  2: "Shouting",
  3: "Feasting",
};

/**
 * Checks if the player has the given Avatar of Boris skill.
 * @param sk Skill to check
 * @return Whether the player has the skill
 */
boolean have_boris_skill(skill sk) {
  // KoLmafia has a glitch where it thinks we have the Ferocity skill from Dark
  // Gyffte. This is a workaround.
  return have_skill(sk) || (sk == $skill[ 11002 ] && have_skill($skill[ 24017 ]));
}

/**
 * Checks if the player has all skills in a list of skills
 * @param sklist Skill list to check
 * @return Whether the player has all the skills
 */
boolean have_all_skill_tree(boolean [skill] sklist) {
  foreach sk in sklist {
    if (!have_boris_skill(sk)) return false;
  }
  return true;
}

/**
 * Generates a better skill table for Avatar of Boris.
 * @param boris_points Amount of Boris skill points you currently have
 * @param vanilla_skill_table HTML for the vanilla skill table. Only used for
 *    sanity checks.
 * @return HTML markup for the improved skill table
 */
string generate_skill_table(int boris_points, string vanilla_skill_table) {
  buffer html;
  html.appendln('<div class="better-trainer-skill-tree">');

  foreach tree_id in AOB_SKILLS {
    html.appendln('  <div class="better-trainer-skill-tree__header-cell">');
    html.appendln(`    {SKILL_TREE_NAMES[tree_id]}`);
    if (have_all_skill_tree(AOB_SKILLS[tree_id])) {
      html.appendln('    <div class="better-trainer-skill-tree__tree-status better-trainer-skill-tree__tree-status--mastered">(Mastered)</div>');
    } else if (boris_points > 0) {
      html.appendln('    <form action="da.php" method="post">');
      html.appendln(`      <input type="hidden" name="whichtree" value="{tree_id}">`);
      html.appendln('      <input type="hidden" name="action" value="borisskill">');
      html.appendln(`      <input class="button better-trainer-skill-tree__unlock-button" type="submit" value="Study {SKILL_TREE_NAMES[tree_id]}">`);
      html.appendln('    </form>');
    }
    html.appendln("  </div>");
  }

  foreach tree_id in AOB_SKILLS {
    boolean is_next_unlock = true;

    // Start at 1 to account for the header row
    int grid_row_num = 1;
    foreach sk in AOB_SKILLS[tree_id] {
      // Sanity check
      if (sk.class != $class[ Avatar of Boris ]) {
        _error(`{sk} is not an Avatar of Boris skill!`);
      }

      ++grid_row_num;
      string cell_classes = "better-trainer-skill-tree__skill-cell";
      string status_classes = "better-trainer-skill-tree__status";
      string status_text = "";
      string status_title = "";
      if (have_boris_skill(sk)) {
        // Sanity check
        if (vanilla_skill_table.contains_text(sk.name)) {
          _debug(`KoLmafia thinks you have {sk}, but the game says it hasn't been learned yet`);
        }

        cell_classes += " better-trainer-skill-tree__skill-cell--owned";
        status_classes += " better-trainer-skill-tree__status--owned";
        status_text = "&#x2714;";
        status_title = "You already learned this skill";
      } else {
        // Sanity check
        if (!vanilla_skill_table.contains_text(sk.name)) {
          _debug(`KoLmafia thinks you don't have {sk}, but the game says you already learned it`);
        }

        if (is_next_unlock) {
          is_next_unlock = false;
          cell_classes += " better-trainer-skill-tree__skill-cell--next-unlock";
          status_classes += " better-trainer-skill-tree__status--next-unlock";
          status_text = "&#x2b9c;";
          status_title = "You will learn this skill when you place a skill point in this tree";
        }
      }

      // Each skill consumes 2 grid columns
      // Column 1 is the skill cell (skill icon and name with tooltips)
      html.appendln(`  <div class="{cell_classes} better-trainer-skill-tooltip" style="grid-row: {grid_row_num}" data-better-trainer-skill-id="{to_int(sk)}">`);
      html.appendln(`    <img class="better-trainer-skill-tree__icon" src="/images/itemimages/{sk.image}">`);
      html.appendln(`    {sk.name}`);
      html.appendln(`  </div>`);
      // Column 2 is the skill status (owned / next unlock / other)
      html.appendln(`  <div class="{status_classes}" style="grid-row: {grid_row_num}" title="{status_title}">{status_text}</div>`);
    }
  }

  html.appendln("</div>");
  return html;
}

/**
 * Extract the amount of Boris skill points you have.
 * @param page HTML of the Boris's Gate page
 * @return Amount of Boris skill points
 */
int parse_boris_points(string page) {
  matcher boris_points_matcher = create_matcher(
    "You can learn (\\d+) more skill", page
  );
  if (boris_points_matcher.find()) {
    return to_int(boris_points_matcher.group(1));
  }
  return 0;
}

/**
 * Relay override script entrypoint.
 */
void main() {
  _debug("Loaded");

  // Check if the user is visiting Boris's Gate (da.php?place=gate1), or has
  // just bought a skill (da.php?action=borisskill)
  if (form_field("place") != "gate1" && form_field("action") != "borisskill") {
    // Do nothing. This causes KoLmafia to present the original page as-is.
    return;
  }

  _debug("Detected Boris' Gate page");
  buffer page = visit_url();

  boolean is_aob = my_class() == $class[ Avatar of Boris ];
  int current_boris_points = parse_boris_points(page);

  // Locate the skill table, which is below the special AoB-specific message.
  // Note: We choose not to use xpath() to extract the outer skill table,
  // because it tries to "clean" bad HTML markup and modifies it. It would
  // prevent us from selectively replacing parts of the page.
  matcher skill_table_matcher = create_matcher(
    "elaborate plaque on the base of the statue[\\s\\S]*?(<table[\\s\\S]*</table>)[\\s\\S]*?In the base of the statue",
    page
  );
  if (!skill_table_matcher.find()) {
    // Sanity check
    if (is_aob) {
      _error("KoLmafia thinks that you are Avatar of Boris, but there is no skill table");
    }
    return;
  } else {
    // Sanity check
    if (!is_aob) {
      _error("KoLmafia thinks that you are not Avatar of Boris, but there is a skill table");
    }
  }
  string vanilla_skill_table = skill_table_matcher.group(1);
  int vanilla_skill_table_start = skill_table_matcher.start(1);
  int vanilla_skill_table_end = skill_table_matcher.end(1);

  _debug("Generating improved skill tree...");

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
  write(generate_skill_table(current_boris_points, vanilla_skill_table));

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
