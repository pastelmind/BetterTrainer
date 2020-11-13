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


// Represents the result of an xpath() match.
record XPathMatch {
  string html;          // Original HTML document
  string selector;      // XPath selector used to retrieve the nodes
  string [int] nodes;   // Matched nodes. Is guaranteed to be a well-formed map.
};


// Creates an XPath match.
XPathMatch xpath_match(string html, string selector) {
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


// Matcher for "block-level" nodes that can be safely split into independent nodes.
// cf. <tr> and <td> must not be split into independent nodes, because xpath()
// will destroy them in an attempt to "clean" the HTML.
// For now, this is a list of tags allowed in <body>, taken from:
// https://developer.mozilla.org/en-US/docs/Web/Guide/HTML/Content_categories#Flow_content
matcher _BLOCK_NODE_MATCHER = create_matcher(`^<(?:a|abbr|address|article|aside|audio|b|bdo|bdi|blockquote|br|button|canvas|cite|code|command|data|datalist|del|details|dfn|div|dl|em|embed|fieldset|figure|footer|form|h1|h2|h3|h4|h5|h6|header|hgroup|hr|i|iframe|img|input|ins|kbd|keygen|label|main|map|mark|math|menu|meter|nav|noscript|object|ol|output|p|picture|pre|progress|q|ruby|s|samp|script|section|select|small|span|strong|sub|sup|svg|table|template|textarea|time|ul|var|video|wbr)`, '');


// Lazy check to see if this is a block node
boolean is_block_node(string node) {
  return _BLOCK_NODE_MATCHER.reset(node).find();
}


// Get a single node in the current match set as a new match set.
XPathMatch get(XPathMatch match, int index) {
  string node = match.nodes[index];
  // If this is a block-level node, it's safe to split off into a new fragment.
  if (is_block_node(node)) {
    // Split the node into a new HTML fragment and "reset" the selector.
    // This makes the HTML and the selector smaller, which makes xpath() faster.
    // The "/body/*[1]" part provides a proper context for chained selectors and
    // prevents the  new "root" node from being accidentally selected.
    // For example, take a look at the following two lines of code:
    //
    //    xpath_match(html, "(//table)[1]//table");
    //    xpath_match(html, "//table").get(0).find("//table");
    //
    // Both lines are meant to be equivalent. If we didn't specify "/body/*[1]",
    // however, the second example would also select the outer table.
    return new XPathMatch(node, "/body/*[1]", { 0: node });
  }
  // Otherwise, reuse the HTML and narrow down the selector.
  // If the current match set contains only one element, don't bother updating the selector.
  string selector = match.nodes.count() == 1 ? match.selector : `({match.selector})[{index + 1}]`;
  return new XPathMatch(match.html, selector, { 0: node });
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
  return match.nodes[0];
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
  return matches[matches.count() - 1].last();
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

  // To replace the original table, we must find the index of the cleaned HTML:
  string cleaned_html = xpath(page, "/[1]")[0];
  int index = cleaned_html.index_of(outer_table.raw());
  print(`Index of outer table: {index}`);

  // Write everything before the original table
  write(cleaned_html.substring(0, index));

  // 2. Find out which skills have been already purchased/permed
  // 3. Build a pretty table

  skill [int][int] guild_skills = class_guild_skills(my_class());

  writeln("<table>");
  writeln("<tbody>");

  foreach level in guild_skills {
    writeln("<tr>");
    writeln(`  <td>Level {level}</td>`);

    foreach _, sk in guild_skills[level] {
      if (trainable_skills contains sk) {
        // Good, the skill is either buyable or unlockable.
        TrainerSkillInfo skill_info = trainable_skills[sk];

        writeln(`<td>{skill_info.node_img}</td>`);
        writeln(`<td>{skill_info.node_skill_name}</td>`);
        writeln(`<td>`);
        writeln(`  <form action="{skill_info.form_action}" style="margin: 0">`);
        if (skill_info.form_action.length() > 0) {
          // The form action exists, and the button is usable
          writeln(`    <button class="button" type="submit">`);
        } else {
          // Skill cannot be purchased because your level is too low.
          // The form action does not exist, and the button is unusable
          writeln(`    <button class="button" type="submit" disabled style="color: #cccccc">`);
        }
        writeln(`      Buy<br><span style="font-size: 75%">{to_string(sk.traincost, "%,d")} meat</span>`);
        writeln(`    </button>`);
        writeln(`    {"".join(skill_info.hidden_inputs)}`);
        writeln(`  </form>`);
        writeln(`</td>`);
      } else {
        // The vanilla trainer page does NOT provide link and images
        // TODO: Generate our own links
        writeln(`<td><img src="/images/itemimages/{sk.image}"></td>`);
        writeln(`<td>{sk}</td>`);
        writeln(`<td>`);
        if (have_skill(sk)) {
          // You already bought or permed the skill
          writeln(`  <div style="text-align: center; color: #00cc00; font-weight: bold: font-size: 300%">&#x2714;</div>`);
        } else {
          // The guild store doesn't display the skill for unknown reason
          writeln(`  <button class="button" type="submit" disabled style="color: #cccccc">N/A</button>`);
        }
        writeln(`</td>`);
      }
    }

    writeln("</tr>");
  }

  writeln("</tbody>");
  writeln("</table>");

  // Write the original table, and everything after it
  write(cleaned_html.substring(index));

  // TODO: When the script fails for some reason, we should write a message so that the user knows about it.
}
