import requests
from bs4 import BeautifulSoup
from urllib.parse import urljoin
from pydantic import BaseModel, Field


class Tools:
    class Valves(BaseModel):
        KIWIX_BASE_URL: str = Field(
            default="http://host.docker.internal:8080",
            description="Base URL of the kiwix-serve instance, a"
        )
        BOOK_NAME: str = Field(
            default="wikipedia_en-simple_all_maxi_2026-06",
            description="ZIM book name/slug to search within. Leave empty to search across all books kiwix-serve is hosting",
        )
        MAX_RESULTS: int = Field(
            default=5, description="Maximum number of search results to return"
        )
        MAX_ARTICLE_CHARS: int = Field(
            default=4000,
            description="Maximum characters of article text to return per fetch, to keep context small",
        )

    def __init__(self):
        self.valves = self.Valves()

    def search_offline_wikipedia(self, query: str) -> str:
        """
        Search the local offline Wikipedia (or other Kiwix library) for articles matching a topic.
        Call this whenever the user asks a factual question,since there is no live internet connection here this offline library is the only source of truth available. Returns matching titles and URLs. follow up with get_offline_article to read one.

        :param query: The topic or question to search for
        :return: A list of matching article titles and URLs, or a message if nothing was found
        """
        try:
            params = {"pattern": query, "pageLength": self.valves.MAX_RESULTS}
            if self.valves.BOOK_NAME:
                params["books.name"] = self.valves.BOOK_NAME
            resp = requests.get(
                f"{self.valves.KIWIX_BASE_URL}/search", params=params, timeout=15
            )
            resp.raise_for_status()
        except Exception as e:
            return f"Error reaching the offline Kiwix server: {e}"

        soup = BeautifulSoup(resp.text, "html.parser")
        seen = set()
        lines = [f"Offline search results for '{query}':"]
        for link in soup.select("a"):
            href = link.get("href", "")
            if "/content/" not in href and "/A/" not in href:
                continue
            full_url = urljoin(self.valves.KIWIX_BASE_URL, href)
            if full_url in seen:
                continue
            seen.add(full_url)
            title = link.get_text(strip=True) or full_url
            lines.append(f"- {title} | {full_url}")
            if len(seen) >= self.valves.MAX_RESULTS:
                break

        if not seen:
            return f"No offline articles found for '{query}'."

        lines.append(
            "\nCall get_offline_article with one of the URLs above to read the full article text."
        )
        return "\n".join(lines)

    def get_offline_article(self, url: str) -> str:
        """
        Fetch the plain-text content of a specific offline article, given a URL returned by
        search_offline_wikipedia

        :param url: The full article URL from a prior search_offline_wikipedia result
        :return: Plain text of the article , or an error message
        """
        try:
            resp = requests.get(url, timeout=15)
            resp.raise_for_status()
        except Exception as e:
            return f"Error fetching article: {e}"

        soup = BeautifulSoup(resp.text, "html.parser")
        for tag in soup(["script", "style", "nav", "footer", "header"]):
            tag.decompose()
        text = soup.get_text("\n", strip=True)
        if not text:
            return "Article had no readable text content."
        return text[: self.valves.MAX_ARTICLE_CHARS]
