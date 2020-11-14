// Helper script for better handling of XPath

script "XPathMatch";


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


// Utility function
// This takes advantage of xpath()'s built-in HTML cleaning functionality to
// "sanitize" a string into a well-formed HTML. It deletes invalid tags and
// wraps everything in <html><head></head><body></body></html>
string xpath_clean_html(string fragment) {
  return xpath(fragment, "/[1]")[0];
}
