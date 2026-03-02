import { useRef, useState } from "react";

// Display a search-query "needle" input field for the props.archiveTarget archive, search the associated text
// json and display the results

export default function GeneralisedArchiveSearchBox(props) {
    const archiveTarget = props.archiveTarget;
    const capitalisedArchiveTarget = archiveTarget.charAt(0).toUpperCase() + archiveTarget.slice(1);
    const indexRef = useRef(null);
    const [needle, setNeedle] = useState("");
    const [results, setResults] = useState([]);
    const [resultsPopupVisible, setResultsPopupVisibility] = useState(false);
    const [guidancePopupVisible, setGuidancePopupVisibility] = useState(false);
    const [hasSearched, setHasSearched] = useState(false);

    async function ensureIndexLoaded() {
        if (indexRef.current) return indexRef.current; // don't download anything if you've already done this

        // firebase.json sets a max-age header on the downloaded_texts.json file of 3 months so once
        // downloaded you can use it for 3 months from cache without refresh. Note that for a first-time user
        // of the webapp, the impact of the extra load will /only/ be felt when the user actually runs a
        // newsletter search and the source file is explicitly requested.
        const res = await fetch("/search_jsons/" + archiveTarget + ".json");
        if (!res.ok) throw new Error(`Failed to load index: ${res.status}`);
        indexRef.current = await res.json(); //indexRef is a useRef, so it persists between renders
        return indexRef.current;
    }

    async function handleSearch(e) {
        e?.preventDefault();

        if (!needle.trim()) {
            return; // do nothing at all if needle is empty
        }

        // Get the text json from /public
        const index = await ensureIndexLoaded();
        const q = needle.toLowerCase();

        // Perform a lower case search
        const hits = [];
        for (const doc of index) {
            const textLower = doc.text.toLowerCase();

            // Count occurrences + capture first match position
            let count = 0;
            let firstIndex = -1;
            let from = 0;

            while (true) { // infnite loop terminated by a "break" instruction
                const i = textLower.indexOf(q, from);
                if (i === -1) break;

                if (firstIndex === -1) firstIndex = i;
                count += 1;
                from = i + q.length; // move past this match (non-overlapping)
            }

            // Push matched texts into "hits" of length 60 chars + length of needle
            if (count > 0) {
                const start = Math.max(0, firstIndex - 30);
                const end = Math.min(doc.text.length, firstIndex + q.length + 30);

                hits.push({
                    filename: doc.filename,
                    snippet: doc.text.slice(start, end),
                    matchCount: count,
                });
            }
        }

        hits.sort((a, b) => {
            // 1) matchCount descending
            if (b.matchCount !== a.matchCount) {
                return b.matchCount - a.matchCount;
            }

            // 2) filename descending (string compare)
            return b.filename.localeCompare(a.filename);
        });

        setResultsPopupVisibility(true);  // open popup only when a needle is specified
        setHasSearched(true);
        setResults(hits);
    }

    // The "snippets" forwarded by handleSearch may be full of html markup. This would have been invisible to
    // the viewer of a Newsletter, but will be in plain sight when viewed in the "matches" list displayed
    // below. The "DOM"-based technique used below was recomended by ChatGPT as the "gold-standard" for this
    // situation. Without this, the display would be the equivalent of using "dangerouslysethtml" 
    function stripTags(str) {
        const div = document.createElement("div");
        div.innerHTML = str;
        return div.textContent || div.innerText || "";
    }

    // return a "boldened" version of the needle within snippet
    function highlight(snippet, needle) {

        var strippedSnippet = stripTags(snippet);

        if (!needle) return strippedSnippet;

        // Escape regex metacharacters in needle
        const escaped = needle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const re = new RegExp(`(${escaped})`, "gi");

        // Split keeps delimiters because of the capturing group (...)
        const parts = strippedSnippet.split(re);

        return parts.map((part, i) =>
            re.test(part) ? <strong key={i}>{part}</strong> : <span key={i}>{part}</span>
        );
    }

    function toggleResultsPopup() {
        setResultsPopupVisibility(prev => !prev);
    }

    var fileRoot = "https://storage.googleapis.com/apparchlive.appspot.com/" + archiveTarget + "/";

    return (
        <div>
            <form onSubmit={handleSearch}
                style={{
                    width: "100%",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    marginBottom: "2vh",
                }} >
                <input
                    style={{
                        border: "0.1vh solid black",
                        height: "4vh",
                        width: "25vw",
                        fontSize: "3vh",
                        marginRight: "2vw",
                    }}
                    value={needle}
                    onChange={(e) => setNeedle(e.target.value)}
                    placeholder={`${capitalisedArchiveTarget} search text ..`}
                />
                <button
                    type="submit"
                    disabled={!needle.trim()}
                    style={{
                        display: "inline-block",
                        margin: "0 0 0 2rem",
                        width: "4rem",
                        height: "5vh",
                        backgroundColor: needle.trim() ? "#007bff" : "#cccccc",
                        color: needle.trim() ? "white" : "#666666",
                        cursor: needle.trim() ? "pointer" : "not-allowed",
                        border: "none",
                        padding: "0rem"
                    }}
                >
                    Search
                </button>
            </form>

            {resultsPopupVisible && (
                <div className="standardpopup" style={{
                    position: 'fixed',
                    top: '28vh',
                    width: '80vw',
                    marginLeft: '-40vw',
                    height: '60vh',
                    paddingTop: "5vh",
                    overflowY: "auto",
                    fontSize: "1rem"
                }}>

                    <div className="standardcancelicon" style={{ right: '.5rem' }}>
                        <img
                            style={{ width: "1.5rem", height: "1.5rem" }}
                            title="Cancel this popup"
                            src="/assets/common_assets/close_icon.png"
                            alt="close button"
                            onClick={() => { toggleResultsPopup(); setGuidancePopupVisibility(false) }}
                        />
                    </div>

                    <button className="selectedapparchbutton"
                        style={{ top: '.5rem', left: '.5rem' }}
                        onClick={() => (setGuidancePopupVisibility(true))}>
                        Guidance
                    </button>

                    <div>
                        {hasSearched && results.length === 0 ? (
                            <div style={{ textAlign: "center" }}>
                                <p>Sorry - couldn't find any newsletters containing string "{needle}"</p>
                            </div>
                        ) : (
                            <ul>
                                {results.map((r, idx) => (
                                    <li key={idx}>
                                        ...<a href={fileRoot + r.filename} target="_blank" rel="noreferrer"
                                            style={{ color: "blue", cursor: "pointer", textDecoration: "none" }}
                                            title={fileRoot + r.filename}>
                                            <strong>{r.filename.slice(-10)}</strong>
                                        </a>
                                        : {highlight(r.snippet, needle)}
                                        {r.matchCount > 1 && (
                                            <strong><em>&nbsp;&nbsp;&nbsp;(+{r.matchCount - 1} more)</em></strong>
                                        )}

                                    </li>
                                ))}
                            </ul>
                        )}
                    </div>
                </div>
            )}


            {guidancePopupVisible && (
                <div className="standardpopup" style={{
                    position: 'fixed',
                    top: '35vh',
                    width: '50vw',
                    marginLeft: '-25vw',
                    height: '40vh',
                    paddingTop: "5vh",
                    overflowY: "auto",
                    fontSize: "1rem"
                }}>

                    <div className="standardcancelicon" style={{ right: '.5rem' }}>
                        <img
                            style={{ width: "1.5rem", height: "1.5rem" }}
                            title="Cancel this popup"
                            src="/assets/common_assets/close_icon.png"
                            alt="close button"
                            onClick={() => (setGuidancePopupVisibility(false))}
                        />
                    </div>

                    <p>Searches are done in lower case and are "partial", so "Brown" will pick up 
                        both "brown" and "Browne".
                    </p>

                    <p>Each line in the results display points to an archive file that contains
                        at least one match with the search text. A short sample of text preceding and
                        following the first match is displayed to provide context. If the file cpntains
                        additional matches, the total number of additional matches is shown in a tag at
                        the end of the line.
                    </p>

                    <p>Non-printable characters in a matched result are displayed as ⟦…⟧
                    </p>

                    <p>Clicking the filename tag at the start of the line will open the archive file pdf
                        original. On a Windows PC, you can use ctrl F to open a search window and locate
                        occurrences of the search text in the pdf file. Some of the archives files have
                        been scanned from paper originals, so the browser may initially display text that
                        is too small to read. On a Windows PC, you can usually enlarge the text-size with
                        repeated ctrl + sequences (ctrl - restores)</p>
                </div>
            )}
        </div>
    )
}
