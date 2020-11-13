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

  // Locate the "Available skills" message
  string [int] xpath_matches = xpath(page, "*/[ contains(text(), 'Available skills') ]");
  foreach _, node in xpath_matches {
    _debug(`Found {node}`);
  }

  // 2. Find out which skills have been already purchased/permed
  // 3. Build a pretty table

  // TODO: When the script fails for some reason, we should write a message so that the user knows about it.
}
