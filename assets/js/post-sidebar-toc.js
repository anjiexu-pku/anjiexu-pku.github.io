(function() {
  function onReady(callback) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", callback);
    } else {
      callback();
    }
  }

  function isVisible(element) {
    return !!(element.offsetWidth || element.offsetHeight || element.getClientRects().length);
  }

  function makeFallbackId(heading, index) {
    var text = heading.textContent || "";
    var slug = text
      .trim()
      .toLowerCase()
      .replace(/[^\w\u0080-\uFFFF]+/g, "-")
      .replace(/^-+|-+$/g, "");

    return "section-" + (slug || "heading") + "-" + index;
  }

  function ensureHeadingId(heading, index) {
    if (!heading.id) {
      heading.id = makeFallbackId(heading, index);
    }

    return heading.id;
  }

  function scrollToHeading(heading) {
    var mastheadOffset = 82;
    var top = heading.getBoundingClientRect().top + window.pageYOffset - mastheadOffset;

    window.scrollTo({
      top: Math.max(0, top),
      behavior: "smooth"
    });
  }

  function syncActiveItemIntoView(sidebar, item) {
    if (!sidebar || !item || sidebar.scrollHeight <= sidebar.clientHeight) {
      return;
    }

    var sidebarRect = sidebar.getBoundingClientRect();
    var itemRect = item.getBoundingClientRect();
    var padding = 18;

    if (itemRect.top < sidebarRect.top + padding) {
      sidebar.scrollTop -= sidebarRect.top + padding - itemRect.top;
    } else if (itemRect.bottom > sidebarRect.bottom - padding) {
      sidebar.scrollTop += itemRect.bottom - (sidebarRect.bottom - padding);
    }
  }

  function initPostSidebarToc() {
    var sidebar = document.querySelector(".sidebar");
    var toc = document.querySelector("[data-post-sidebar-toc]");
    var content = document.querySelector(".page__content");

    if (!sidebar || !toc || !content) {
      return;
    }

    var menu = toc.querySelector(".post-sidebar-toc__menu");
    var titleText = toc.querySelector(".post-sidebar-toc__title-text");
    var selector = toc.getAttribute("data-toc-selector") || "h2";
    var sections = [];
    var activeSection = null;
    var ticking = false;

    function isChineseMode() {
      var activeSwitch = document.querySelector(".lang-switch a.active");

      if (!activeSwitch) {
        return false;
      }

      var href = activeSwitch.getAttribute("href") || "";
      var text = activeSwitch.textContent || "";

      return href === "#zh" || /中文|Chinese\s*\(中文\)/i.test(text);
    }

    function updateTocTitle() {
      var title = toc.getAttribute(isChineseMode() ? "data-toc-title-zh" : "data-toc-title-en") || "Contents";

      if (titleText) {
        titleText.textContent = title;
      }
      toc.setAttribute("aria-label", title);
    }

    function clearActive() {
      sections.forEach(function(section) {
        section.item.classList.remove("is-active");
        section.link.removeAttribute("aria-current");
      });
    }

    function setActive(section) {
      if (!section || section === activeSection) {
        return;
      }

      clearActive();
      section.item.classList.add("is-active");
      section.link.setAttribute("aria-current", "location");
      activeSection = section;
      syncActiveItemIntoView(sidebar, section.item);
    }

    function findCurrentSection() {
      var anchorLine = window.pageYOffset + 120;
      var current = sections[0];

      sections.forEach(function(section) {
        if (section.heading.offsetTop <= anchorLine) {
          current = section;
        }
      });

      return current;
    }

    function updateActiveSection() {
      ticking = false;

      if (sections.length) {
        setActive(findCurrentSection());
      }
    }

    function requestUpdate() {
      if (!ticking) {
        ticking = true;
        window.requestAnimationFrame(updateActiveSection);
      }
    }

    function createMenuItem(heading, index) {
      var level = parseInt(heading.tagName.slice(1), 10);
      var li = document.createElement("li");
      var link = document.createElement("a");
      var id = ensureHeadingId(heading, index);

      li.className = "post-sidebar-toc__item post-sidebar-toc__item--h" + level;
      link.href = "#" + encodeURIComponent(id);
      link.textContent = heading.textContent.trim().replace(/\s+/g, " ");
      li.appendChild(link);

      link.addEventListener("click", function(event) {
        event.preventDefault();
        setActive(sections.find(function(section) {
          return section.heading === heading;
        }));
        history.pushState(null, "", "#" + encodeURIComponent(id));
        scrollToHeading(heading);
      });

      return { item: li, link: link, heading: heading, level: level };
    }

    function appendMenuItem(section, lastByLevel, baseLevel) {
      var parentLevel = section.level - 1;
      var parent = lastByLevel[parentLevel];

      if (section.level <= baseLevel || !parent) {
        menu.appendChild(section.item);
      } else {
        var childList = parent.item.querySelector(":scope > ul");
        if (!childList) {
          childList = document.createElement("ul");
          parent.item.appendChild(childList);
        }
        childList.appendChild(section.item);
      }

      Object.keys(lastByLevel).forEach(function(level) {
        if (parseInt(level, 10) >= section.level) {
          delete lastByLevel[level];
        }
      });
      lastByLevel[section.level] = section;
    }

    function buildToc() {
      updateTocTitle();

      var headings = Array.prototype.slice.call(content.querySelectorAll(selector)).filter(function(heading) {
        return heading.textContent.trim() && isVisible(heading) && !heading.closest("[data-post-sidebar-toc]");
      });

      sections = [];
      activeSection = null;
      menu.innerHTML = "";

      if (headings.length < 2) {
        toc.hidden = true;
        sidebar.classList.remove("sidebar--with-post-toc");
        return;
      }

      var baseLevel = headings.reduce(function(min, heading) {
        return Math.min(min, parseInt(heading.tagName.slice(1), 10));
      }, 6);
      var lastByLevel = {};

      headings.forEach(function(heading, index) {
        var section = createMenuItem(heading, index);
        sections.push(section);
        appendMenuItem(section, lastByLevel, baseLevel);
      });

      toc.hidden = false;
      sidebar.classList.add("sidebar--with-post-toc");
      requestUpdate();
    }

    buildToc();
    window.addEventListener("scroll", requestUpdate, { passive: true });
    window.addEventListener("resize", requestUpdate);

    Array.prototype.slice.call(document.querySelectorAll(".lang-switch a")).forEach(function(link) {
      link.addEventListener("click", function() {
        window.setTimeout(buildToc, 0);
      });
    });
  }

  onReady(initPostSidebarToc);
})();
