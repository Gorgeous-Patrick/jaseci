let pyodideWorker = null;
let pyodideReady = false;
let pyodideInitPromise = null;
let monacoLoaded = false;
let monacoLoadPromise = null;

// Initialize Pyodide Worker
function initPyodideWorker() {
    if (pyodideWorker) return pyodideInitPromise;
    pyodideWorker = new Worker("/js/pyodide-worker.js");
    pyodideInitPromise = new Promise((resolve, reject) => {
        pyodideWorker.onmessage = (event) => {
            if (event.data.type === "ready") {
                pyodideReady = true;
                resolve();
            }
        };
        pyodideWorker.onerror = (e) => reject(e);
    });
    pyodideWorker.postMessage({ type: "init" });
    return pyodideInitPromise;
}

// Run Jac Code in Worker
function runJacCodeInWorker(code) {
    return new Promise(async (resolve, reject) => {
        await initPyodideWorker();
        const handleMessage = (event) => {
            if (event.data.type === "result") {
                pyodideWorker.removeEventListener("message", handleMessage);
                resolve(event.data.output);
            } else if (event.data.type === "error") {
                pyodideWorker.removeEventListener("message", handleMessage);
                reject(event.data.error);
            }
        };
        pyodideWorker.addEventListener("message", handleMessage);
        pyodideWorker.postMessage({ type: "run", code });
    });
}

// Load Monaco Editor Globally
function loadMonacoEditor() {
    if (monacoLoaded) return monacoLoadPromise;
    if (monacoLoadPromise) return monacoLoadPromise;

    monacoLoadPromise = new Promise((resolve, reject) => {
        require.config({ paths: { vs: 'https://cdn.jsdelivr.net/npm/monaco-editor@0.52.2/min/vs' } });
        require(['vs/editor/editor.main'], function () {
            monacoLoaded = true;
            resolve();
        }, reject);
    });
    console.log("Loading Monaco Editor...");
    return monacoLoadPromise;
}

// Setup Code Block with Monaco Editor
async function setupCodeBlock(div) {
    if (div._monacoInitialized) return;
    div._monacoInitialized = true;

    const originalCode = div.textContent.trim();

    div.innerHTML = `
        <div class="jac-code-loading" style="padding: 10px; font-style: italic; color: gray;">
            Loading editor...
        </div>
    `;

    await loadMonacoEditor();

    div.innerHTML = `
    <div class="jac-code" style="border: 1px solid #ccc;"></div>
    <button class="md-button md-button--primary run-code-btn">Run</button>
    <pre class="code-output" style="display:none; white-space: pre-wrap; background: #1e1e1e; color: #d4d4d4; padding: 10px;"></pre>
    `;

    const container = div.querySelector(".jac-code");
    const runButton = div.querySelector(".run-code-btn");
    const outputBlock = div.querySelector(".code-output");

    const editor = monaco.editor.create(container, {
        value: originalCode || '# Write your Jac code here',
        language: 'python',
        theme: 'vs-dark',
        scrollBeyondLastLine: false,
        scrollbar: {
            vertical: 'hidden',
            handleMouseWheel: false,
        },
        automaticLayout: true,
        padding: {
            top: 10,
            bottom: 10
        }
    });

    function updateEditorHeight() {
        const lineCount = editor.getModel().getLineCount();
        const lineHeight = editor.getOption(monaco.editor.EditorOption.lineHeight);
        const height = lineCount * lineHeight + 20;
        container.style.height = `${height}px`;
        editor.layout();
    }

    updateEditorHeight();
    editor.onDidChangeModelContent(updateEditorHeight);

    runButton.addEventListener("click", async () => {
        outputBlock.style.display = "block";

        if (!pyodideReady) {
            outputBlock.textContent = "Loading Jac runner...";
            await initPyodideWorker();
        }

        outputBlock.textContent = "Running...";
        try {
            const codeToRun = editor.getValue();
            const result = await runJacCodeInWorker(codeToRun);
            outputBlock.textContent = `Output:\n${result}`;
        } catch (error) {
            outputBlock.textContent = `Error:\n${error}`;
        }
    });
}

const observer = new MutationObserver(() => {
    document.querySelectorAll('.code-block').forEach(setupCodeBlock);
});

observer.observe(document.body, {
    childList: true,
    subtree: true
});

document.addEventListener("DOMContentLoaded", async () => {
    initPyodideWorker();
});
