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

    // Manually track whether the <iframe> is loaded, because
    // iframe.contentDocument.readyState seems to be unreliable
    let isContentLoaded = false;

    const tooltipContent = document.createElement("div");

    const skillDescLoader = () => {
      if (!isContentLoaded) return "Loading...";

      // Reset the tooltip contents, overriding any secondary pages that the
      // user may have visited
      tooltipContent.innerHTML = iframe.contentDocument.getElementById('description').innerHTML;
      return tooltipContent;
    };

    const tippyInstance = tippy(tooltipElem, {
      allowHTML: true,
      content: skillDescLoader,
      delay: 300,
      duration: 100,
      interactive: true,
      onHidden: (instance) => {
        // Reset the tooltip contents, overriding any secondary pages that the
        // user may have visited
        instance.setContent(skillDescLoader);
      },
      placement: "left-end",
    });

    // If the user clicks on a link inside the skill description (e.g. the
    // effect description for a buff skill), load the secondary page and
    // replace the contents of the div
    tooltipContent.addEventListener("click", (event) => {
      if (!(event.target.tagName === "A" && event.target.href)) return;

      event.preventDefault();

      fetch(event.target.href)
        .then((response) => {
          if (!response.ok) {
            throw new Error(`HTTP ${response.status} ${response.statusText}`);
          }
          return response.text();
        })
        .then((html) => {
          tippyInstance.setContent(extractDescriptionFragment(html));
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

    iframe.addEventListener("load", () => {
      isContentLoaded = true;
      // Must be called to resize the tooltip
      tippyInstance.setContent(skillDescLoader);
    });
  }
});
