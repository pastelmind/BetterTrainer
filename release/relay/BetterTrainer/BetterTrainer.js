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

document.addEventListener("DOMContentLoaded", () => {
  // Manually loop through each element to preload <iframe>s
  for (const tooltipElem of document.getElementsByClassName(
    "better-trainer-skill-tooltip"
  )) {
    // Preload the skill description page using an <iframe>
    const iframe = document.createElement("iframe");
    iframe.src = tooltipElem.dataset.betterTrainerDescUrl;
    iframe.style.display = "none";
    document.body.appendChild(iframe);

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
      onHidden: (instance) => {
        // Reset the tooltip contents, overriding any secondary pages that the
        // user may have visited
        instance.setContent(tooltipContent);
      },
      placement: "left-end",
    });

    iframe.addEventListener("load", () => {
      // Create a <div> tag to hold the actual tooltip contents
      tooltipContent = document.createElement("div");
      tooltipContent.innerHTML = iframe.contentDocument.getElementById(
        "description"
      ).innerHTML;

      // If the user clicks on a link inside the skill description (e.g. the
      // effect description for a buff skill), load the secondary page and
      // replace the contents of the div
      tooltipContent.addEventListener("click", (event) => {
        if (!(event.target.tagName === "A" && event.target.href)) return;

        event.preventDefault();

        fetchDescription(event.target.href)
          .then((descriptionFragment) => {
            tippyInstance.setContent(descriptionFragment);
          })
          .catch((error) => {
            tippyInstance.setContent("Failed to load page");
            console.error(
              "Failed to fetch link:",
              event.target.href,
              "\nReason:",
              error
            );
          });
      });

      // Show the updated tooltip content
      tippyInstance.setContent(tooltipContent);
    });
  }
});
