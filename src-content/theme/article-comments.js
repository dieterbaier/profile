(function () {
    "use strict";

    function renderIssues(container, issues) {
        const list = container.querySelector(".article-comments-list");
        const status = container.querySelector(".article-comments-status");
        list.replaceChildren();

        if (issues.length === 0) {
            status.textContent = "Noch keine Kommentare vorhanden.";
            return;
        }

        issues.forEach(function (issue) {
            const item = document.createElement("li");
            const link = document.createElement("a");
            link.href = issue.html_url;
            link.textContent = issue.title;
            link.target = "_blank";
            link.rel = "noopener noreferrer";
            item.appendChild(link);
            list.appendChild(item);
        });
        status.textContent = issues.length === 1 ? "Ein Kommentar:" : issues.length + " Kommentare:";
    }

    async function loadIssues(container, button) {
        const repository = container.dataset.repository;
        const marker = container.dataset.issueMarker;
        const status = container.querySelector(".article-comments-status");
        const endpoint = "https://api.github.com/repos/" + repository + "/issues?state=all&per_page=100&sort=created&direction=desc";

        button.disabled = true;
        status.textContent = "Kommentare werden von GitHub geladen …";

        try {
            const response = await fetch(endpoint, { headers: { Accept: "application/vnd.github+json" } });
            if (!response.ok) throw new Error("GitHub API returned " + response.status);
            const issues = (await response.json()).filter(function (issue) {
                return !issue.pull_request && issue.title.indexOf(marker) !== -1;
            });
            renderIssues(container, issues);
            button.hidden = true;
        } catch (error) {
            status.textContent = "Kommentare konnten derzeit nicht geladen werden. Bitte versuchen Sie es später erneut.";
            button.disabled = false;
        }
    }

    document.querySelectorAll("[data-article-comments]").forEach(function (container) {
        const button = container.querySelector(".article-comments-load");
        if (button) button.addEventListener("click", function () { loadIssues(container, button); });
    });
})();
