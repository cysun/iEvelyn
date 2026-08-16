import Foundation

nonisolated enum MarkdownStyles {
    static let reader = common + """

    :root {
      color-scheme: light dark;
      --page: #ffffff;
      --text: #202124;
      --secondary: #62666d;
      --accent: #315f9b;
      --border: #d9dce1;
      --surface: #f5f6f8;
      --quote: #e8eef7;
      --warning: #fff4d6;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --page: #1d1d1f;
        --text: #f2f2f4;
        --secondary: #b2b4ba;
        --accent: #8ab4ef;
        --border: #45464c;
        --surface: #292a2f;
        --quote: #27364b;
        --warning: #4b3b18;
      }
    }

    html, body { background: var(--page); color: var(--text); }
    body { padding: 1.35rem clamp(1rem, 4vw, 2.5rem); }
    .chapter { max-width: 48rem; margin: 0 auto; }
    a { color: var(--accent); text-decoration-thickness: 0.08em; text-underline-offset: 0.14em; }
    a:focus-visible { outline: 0.18rem solid var(--accent); outline-offset: 0.15rem; }
    """

    static let epub = common + """

    html, body { color: #202124; background: #ffffff; }
    body { margin: 0 5%; }
    .chapter { max-width: 48rem; margin: 0 auto; }
    a { color: #315f9b; }
    """

    private static let common = """
    * { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0;
      font-family: ui-serif, Georgia, "Times New Roman", serif;
      font-size: 1rem;
      line-height: 1.65;
      overflow-wrap: anywhere;
    }
    h1, h2, h3, h4, h5, h6 {
      margin: 1.65em 0 0.55em;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
      line-height: 1.2;
      text-wrap: balance;
    }
    h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
    p { margin: 0.85em 0; }
    strong { font-weight: 700; }
    blockquote {
      margin: 1.2em 0;
      padding: 0.15em 1em;
      border-inline-start: 0.3em solid var(--accent, #315f9b);
      background: var(--quote, #e8eef7);
    }
    blockquote > :first-child { margin-top: 0.5em; }
    blockquote > :last-child { margin-bottom: 0.5em; }
    ul, ol { padding-inline-start: 1.8em; }
    li { margin: 0.3em 0; }
    li > p { margin: 0.25em 0; }
    .task-list-item { list-style: none; margin-inline-start: -1.35em; }
    .task-list-item input { margin-inline-end: 0.55em; }
    code, pre {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.9em;
    }
    code {
      padding: 0.12em 0.3em;
      border-radius: 0.3em;
      background: var(--surface, #f5f6f8);
    }
    pre {
      max-width: 100%;
      overflow-x: auto;
      padding: 1em;
      border: 0.08em solid var(--border, #d9dce1);
      border-radius: 0.55em;
      background: var(--surface, #f5f6f8);
      line-height: 1.45;
      white-space: pre;
    }
    pre code { padding: 0; background: transparent; }
    .raw-html, .unsupported-markup {
      border-inline-start: 0.3em solid #c48716;
      background: var(--warning, #fff4d6);
    }
    hr { margin: 2em 0; border: 0; border-top: 0.08em solid var(--border, #d9dce1); }
    img { display: block; max-width: 100%; height: auto; margin: 1.2em auto; }
    .unavailable-image {
      display: inline-block;
      padding: 0.55em 0.75em;
      border: 0.08em dashed var(--border, #d9dce1);
      border-radius: 0.4em;
      color: var(--secondary, #62666d);
    }
    .table-scroll { max-width: 100%; overflow-x: auto; margin: 1.2em 0; }
    table { width: 100%; border-collapse: collapse; }
    th, td {
      padding: 0.5em 0.7em;
      border: 0.08em solid var(--border, #d9dce1);
      text-align: start;
      vertical-align: top;
    }
    th { font-family: ui-sans-serif, -apple-system, sans-serif; background: var(--surface, #f5f6f8); }
    .align-left { text-align: left; }
    .align-center { text-align: center; }
    .align-right { text-align: right; }
    .sr-only {
      position: absolute;
      width: 1px;
      height: 1px;
      padding: 0;
      margin: -1px;
      overflow: hidden;
      clip: rect(0, 0, 0, 0);
      white-space: nowrap;
      border: 0;
    }
    """
}
