<!-- omit from toc -->
# gh_grep Usage Guide — GitHub Code Search

[![gh-grep Plugin][ghgrep-shield]][ghgrep-url]

> **Source**: `@morphllm/opencode-morph-plugin` ([github.com/morphllm/opencode-morph-plugin](https://github.com/morphllm/opencode-morph-plugin))
> **Tool**: `gh_grep_searchGitHub` — search 1M+ public repos for real-world code examples

## Tool

| Tool                   | What it does                                             |
|------------------------|----------------------------------------------------------|
| `gh_grep_searchGitHub` | Find real-world code patterns across public GitHub repos |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## When to use

| When you need…                     | Use                                                                                             |
|------------------------------------|-------------------------------------------------------------------------------------------------|
| Real-world usage of an API/library | `gh_grep_searchGitHub({query: "getServerSession", language: ["TypeScript"]})`                   |
| How others implement a pattern     | `gh_grep_searchGitHub({query: "ErrorBoundary", language: ["TSX"]})`                             |
| Correct syntax/configuration       | `gh_grep_searchGitHub({query: "CORS(", language: ["Python"], matchCase: true})`                 |
| Multi-line patterns                | `gh_grep_searchGitHub({query: "(?s)useEffect\\(\\(\\).*removeEventListener", useRegexp: true})` |

## Tips

- Search for **literal code patterns**, not keywords or questions
- Use `"useRegexp: true"` with `"(?s)"` prefix for multi-line patterns

- Filter by `language`, `repo`, or `path` for targeted results
- Good: `"useState("`, `"async function"`, `"import React from"`

- Bad: `"react tutorial"`, `"best practices"`
[ghgrep-shield]: https://img.shields.io/badge/gh--grep-Plugin-blue?style=for-the-badge
[ghgrep-url]: #

