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
        const perPage = 100;
        const searchLimit = 1000;
        const query = "repo:" + repository + " in:title \"" + marker + "\"";
        const endpoint = "https://api.github.com/search/issues?q=" + encodeURIComponent(query) +
            "&sort=created&order=desc&per_page=" + perPage;

        button.disabled = true;
        status.textContent = "Kommentare werden von GitHub geladen …";

        try {
            const issues = [];
            let page = 1;
            let resultCount = 0;

            do {
                const response = await fetch(endpoint + "&page=" + page, {
                    headers: { Accept: "application/vnd.github+json" }
                });
                if (!response.ok) throw new Error("GitHub API returned " + response.status);

                const result = await response.json();
                if (result.incomplete_results) throw new Error("GitHub search returned incomplete results");
                if (result.total_count > searchLimit) throw new Error("GitHub search result limit exceeded");
                resultCount = Math.min(result.total_count, searchLimit);
                issues.push.apply(issues, result.items);
                page += 1;
            } while (issues.length < resultCount);

            const matchingIssues = issues.filter(function (issue) {
                return !issue.pull_request && issue.title.indexOf(marker) !== -1;
            });
            renderIssues(container, matchingIssues);
            button.hidden = true;
        } catch (error) {
            status.textContent = "Kommentare konnten derzeit nicht geladen werden. Bitte versuchen Sie es später erneut.";
            button.disabled = false;
        }
    }

    document.querySelectorAll("[data-article-comments]").forEach(function (container) {
        const button = container.querySelector(".article-comments-load");
        if (button) button.addEventListener("click", function () { return loadIssues(container, button); });
    });
})();
