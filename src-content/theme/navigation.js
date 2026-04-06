(function () {
    const nav = document.getElementById("mainnav");
    if (!nav) return;

    const toggle = nav.querySelector(".nav-toggle");
    const closeBtn = nav.querySelector(".nav-close");
    const overlay = nav.querySelector(".nav-overlay");
    const drawer = nav.querySelector(".nav-drawer");
    const links = nav.querySelectorAll(".nav-drawer a");

    if (!toggle || !closeBtn || !overlay || !drawer) return;

    function openNav() {
        nav.classList.add("open");
        toggle.setAttribute("aria-expanded", "true");
        closeBtn.focus();
        document.body.style.overflow = "hidden";
    }

    function closeNav() {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
        document.body.style.overflow = "";
        toggle.focus();
    }

    function isMobile() {
        return window.matchMedia("(max-width: 700px)").matches;
    }

    toggle.addEventListener("click", function () {
        if (nav.classList.contains("open")) {
            closeNav();
        } else {
            openNav();
        }
    });

    closeBtn.addEventListener("click", closeNav);
    overlay.addEventListener("click", closeNav);

    document.addEventListener("keydown", function (event) {
        if (event.key === "Escape" && nav.classList.contains("open")) {
            closeNav();
        }
    });

    links.forEach(function (link) {
        link.addEventListener("click", function () {
            if (isMobile()) {
                closeNav();
            }
        });
    });

    window.addEventListener("resize", function () {
        if (!isMobile() && nav.classList.contains("open")) {
            nav.classList.remove("open");
            toggle.setAttribute("aria-expanded", "false");
            document.body.style.overflow = "";
        }
    });
})();