// This script is loosely based on the Improved Guild Trainer by rbond86.
// For their work, see:
// - Original thread: https://kolmafia.us/threads/improved-guild-trainer.13972/
// - Repository: https://sourceforge.net/projects/rlbond86-mafia-scripts/

script "BetterTrainer";


boolean __DEBUG__ = true;

// Prints a debug message to the CLI
void _debug(string msg) {
  if (__DEBUG__) print(`[relay/guild.ash][{time_to_string()}] {msg}`);
}

// Prints a debug message to the CLI and aborts the script
void _error(string msg) {
  abort(`[relay/guild.ash][{time_to_string()}] ERROR: {msg}`);
}


// Represents the result of an xpath() match result.
// Because xpath() attempts to "clean" HTML fragments into well-formed HTML,
// we cannot call xpath() on a node fragment without ruining it.
record XPathMatch {
  string html;          // Original HTML document
  string selector;      // XPath selector used to retrieve the nodes
  string [int] nodes;   // Matched nodes. Is guaranteed to be a well-formed map.
};


// Creates an XPath match.
XPathMatch xpath_match(string html, string selector) {
  _debug(`xpath() called with {selector}`);
  return new XPathMatch(html, selector, xpath(html, selector));
}


// Returns the number of matched nodes in the XPathMatch.
int count(XPathMatch match) {
  return match.nodes.count();
}


// Checks if the given match set is empty.
boolean empty(XPathMatch match) {
  return match.count() == 0;
}


// Creates a new XPath match set from an existing match set.
// This simply appends the given selector to the current selector.
XPathMatch find(XPathMatch match, string selector) {
  return xpath_match(match.html, match.selector + selector);
}


// Get a single node in the current match set as a new match set.
XPathMatch get(XPathMatch match, int index) {
  // If the current match set has only one element,
  // don't bother adding an order selector
  string selector = match.nodes.count() == 1 ? match.selector : `({match.selector})[{index + 1}]`;
  return new XPathMatch(match.html, selector, { 0: match.nodes[index] });
}


// Alias for XPathMatch.get(0)
XPathMatch first(XPathMatch match) {
  return match.get(0);
}


// Alias for XPathMatch.get(XPathMatch.count() - 1)
XPathMatch last(XPathMatch match) {
  return match.get(match.count() - 1);
}


// Returns the raw string for the match node at the given index.
string raw(XPathMatch match, int index) {
  return match.nodes[index];
}


// Alias for match.raw(0)
string raw(XPathMatch match) {
  return match.raw(0);
}


// Helper function for iterating through a match set.
// Returns a list of singular match sets from a given match set.
XPathMatch [int] items(XPathMatch match) {
  XPathMatch [int] the_items;
  foreach index in match.nodes {
    the_items[index] = match.get(index);
  }
  return the_items;
}


// Returns a list of singular match sets that contain the given substring `text`.
// Due to limitations with xpath(), this returns a map of int => XPathMatch.
XPathMatch [int] containing(XPathMatch match, string text) {
  XPathMatch [int] results;
  foreach index, node in match.nodes {
    if (node.contains_text(text)) {
      results[results.count()] = match.get(index);
    }
  }
  return results;
}


// Returns a list of singular match sets that match a regular expression.
// Due to limitations with xpath(), this returns a map of int => XPathMatch.
XPathMatch [int] matching(XPathMatch match, string pattern) {
  XPathMatch [int] results;
  foreach index, node in match.nodes {
    if (create_matcher(pattern, node).find()) {
      results[results.count()] = match.get(index);
    }
  }
  return results;
}


// Helper function for handling lists of XPathMatch records.
// Returns the first item in a list of match sets.
XPathMatch first(XPathMatch [int] matches) {
  return matches[0].first();
}


// Helper function for handling lists of XPathMatch records.
// Returns the last item in a list of match sets.
XPathMatch last(XPathMatch [int] matches) {
  return matches[0].last();
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

  foreach the_skill in $skills[] {
    // All skills have a level between -1 and 15, inclusive.
    // -1 means the skill does not have a level, and is not a guild skill.
    // 0 means the skill is a starting skill, and therefore not a guild skill.
    // 1~15 means the skill is a guild skill.
    if (the_skill.class == the_class && the_skill.level > 0) {
      // Sanity check, probably unnecessary
      if (the_skill.traincost <= 0) {
        _debug(`{the_skill} appears to be a guild skill, but does not have an associated training cost.`);
      }

      skill [int] skills_of_level = guild_skills[the_skill.level];
      skills_of_level[skills_of_level.count()] = the_skill;
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
  // string LEVEL_PATTERN = "Level (\\d+)";
  // string level_text = row_node.find("//td").matching(LEVEL_PATTERN).last().raw();

  // matcher m = create_matcher(LEVEL_PATTERN, level_text);
  // if (!m.find()) {
  //   _error(`This should be unreachable. Cannot find "{LEVEL_PATTERN}" although it was already matched.`);
  // }
  // int level_from_text = to_int(m.group(1));
  // if (the_skill.level != level_from_text) {
  //   _debug(`KoLmafia believes that {the_skill} has a level of {the_skill.level}, but the game says that it's actually {level_from_text}`);
  // }

  // Build the skill info record
  string node_img = row_node.find("//img").raw();
  XPathMatch form = row_node.find("//form");
  string form_action;
  form_action = row_node.find("//form/@action").raw();
  string [int] hidden_inputs = row_node.find("//input[@type='hidden']").nodes;
  return new TrainerSkillInfo(
    the_skill, node_img, node_skill_name.raw(), form_action, hidden_inputs
  );
}


void main() {
  _debug("Loaded");

  // Check if the user is visiting the guild trainer (guild.php?place=trainer)
  if (form_field("place") != "trainer") {
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

  // Iterate through the <tr>s of the *inner* <table> inside the outer <table>
  // and construct a map of trainable skills
  TrainerSkillInfo [skill] trainable_skills;
  foreach _, table_row in outer_table.find("//table//tr").items() {
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

  // 2. Find out which skills have been already purchased/permed
  // 3. Build a pretty table

  // TODO: When the script fails for some reason, we should write a message so that the user knows about it.
}
