/**
 * BetterTrainer (guild.ash) skill popup code
 */

/**
 * Parses the HTML source of a skill/effect page and extracts the DOM nodes
 * containing the description.
 * @param {string} html HTML source of the page
 * @returns {DocumentFragment} DocumentFragment containing the description
 * @throws {Error} If the description element cannot be extracted
 */
function extractDescriptionFragment(html) {
  const parser = new DOMParser();
  const doc = parser.parseFromString(html, "text/html");

  const elementId = "description";
  const descriptionElem = doc.getElementById(elementId);
  if (!descriptionElem) {
    throw new Error(`Cannot find element with ID "${elementId}"`);
  }

  const fragment = document.createDocumentFragment();
  for (const child of descriptionElem.children) {
    fragment.appendChild(document.importNode(child, true));
  }
  return fragment;
}

/**
 * Fetches the URL for a skill/effect page and extracts the description.
 * @param {string} url URL of the page
 * @returns {Promise<DocumentFragment>} DocumentFragment containing the
 *    description
 * @throws {Error} If the page cannot be retrieved or the description cannot be
 *    extracted
 */
async function fetchDescription(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${response.statusText}`);
  }
  const html = await response.text();

  return extractDescriptionFragment(html);
}

/**
 * Extracts the skill description URL from the element's data attributes.
 * @param {HTMLElement} element Element to inspect
 * @returns {string} Skill description URL
 * @throws {Error} If the description URL cannot be extracted
 */
function extractDescriptionUrl(element) {
  if (element.dataset.betterTrainerDescUrl) {
    return element.dataset.betterTrainerDescUrl;
  }
  if (element.dataset.betterTrainerSkillId) {
    return `desc_skill.php?whichskill=${element.dataset.betterTrainerSkillId}&self=true`;
  }

  throw new Error(`Cannot find skill ID in element ${element}`);
}

/**
 * Prints a detailed error message to the browser console.
 * @param {Error} error Error caught while trying to load a URL
 * @param {string} url  URL that caused an error
 */
function reportFetchError(error, url) {
  console.error(`Failed to fetch URL: ${url}\nReason: ${error.stack}`);
}

/**
 * URL patterns for pages that can be browsed within the tooltip popup.
 * Pages that require a direct visit (e.g. a shop) are filtered by this pattern.
 */
const tooltipViewableUrlPattern = /(?:desc_skill|desc_effect|desc_familiar|desc_item)\.php/i;

/**
 * Adds description tooltip to a HTML element.
 * @param {HTMLElement} tooltipElem Element to apply add tooltips
 */
async function setupTooltip(tooltipElem) {
  /**
   * Primary tooltip content. This is either a loading message or the loaded
   * skill description.
   * @type {string | HTMLElement}
   */
  let tooltipContent = "Loading...";

  const tippyInstance = tippy(tooltipElem, {
    allowHTML: true,
    content: tooltipContent,
    delay: 300,
    duration: 100,
    interactive: true,
    maxWidth: 300,
    onHidden: (instance) => {
      // Reset the tooltip contents, overriding any secondary pages that the
      // user may have visited
      instance.setContent(tooltipContent);
    },
    placement: "left-end",
  });

  try {
    // Preload the skill description page
    const skillDescFragment = await fetchDescription(
      extractDescriptionUrl(tooltipElem)
    );

    // Create a <div> tag to hold the actual tooltip contents
    tooltipContent = document.createElement("div");
    tooltipContent.appendChild(skillDescFragment);

    // If the user clicks on a link inside the skill description (e.g. the
    // effect description for a buff skill), load the secondary page and
    // replace the contents of the div
    tippyInstance.popper.addEventListener("click", async (event) => {
      if (!(event.target.tagName === "A" && event.target.href)) return;
      if (!tooltipViewableUrlPattern.test(event.target.href)) return;

      event.preventDefault();

      try {
        const effectDescFragment = await fetchDescription(event.target.href);
        tippyInstance.setContent(effectDescFragment);
      } catch (error) {
        tippyInstance.setContent("Failed to load page");
        reportFetchError(error, event.target.href);
      }
    });

    // Show the updated tooltip content
    tippyInstance.setContent(tooltipContent);
  } catch (error) {
    tippyInstance.setContent("Failed to load page");
    reportFetchError(error, tooltipElem.dataset.betterTrainerDescUrl);
  }
}

document.addEventListener("DOMContentLoaded", () => {
  // Manually loop through each element to preload <iframe>s
  for (const tooltipElem of document.getElementsByClassName(
    "better-trainer-skill-tooltip"
  )) {
    // Note: Do not use await here to allow all requests to fire at once.
    setupTooltip(/** @type {HTMLElement} */ (tooltipElem));
  }
});
