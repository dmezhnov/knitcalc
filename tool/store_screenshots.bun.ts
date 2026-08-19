// Re-captures the phone screenshots every store listing uses
// (packaging/metadata/screenshots/<locale>/phone/) by driving the published web
// build with headless Chrome over CDP. Run it through `mise screenshots`, and
// run `mise metadata` afterwards so the fastlane copies follow.
//
// It shoots the same three screens per locale — the calculator with a filled
// swatch and its results, the save dialog, and the project list with two saved
// projects — at 1080x1920, which is 9:16 exactly: the ratio RuStore demands and
// the one Play and IzzyOnDroid accept unchanged.
//
// Flutter paints into a canvas, so there is nothing to query until the
// accessibility tree exists (built by clicking the semantics placeholder) and
// nothing to type into either: assigning input.value never reaches Flutter's
// editing model, so every field is tapped with Input.dispatchMouseEvent and
// filled with Input.insertText.

// Bun has no temp-directory API of its own, and Chrome needs a real profile
// directory to write DevToolsActivePort into.
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

/// Screens, in the order the store listings show them.
const shots = ['calculator', 'project', 'projects'] as const;

/// Everything the script has to recognize on screen, per locale. The UI strings
/// are the ones in lib/l10n/app_<lang>.arb; `dir` is the screenshot directory,
/// which is also fastlane's locale spelling.
const locales = {
    en: {
        dir: 'en-US',
        // The app always starts in Russian, so English is reached through the
        // app bar's globe, whose semantics label is the current language.
        switchFrom: 'Русский',
        switchTo: 'English',
        save: 'Save',
        back: 'Back',
        name: 'Name',
        description: 'Description',
        newProject: 'New',
        fromType: 'Rectangular scarf',
        toType: 'Triangular shawl',
        projects: [
            ['Scarf for Mum', 'Alize Lanagold yarn, 3.5 mm needles, 2x2 rib'],
            ['Mohair shawl', 'Kid mohair held double, 4 mm needles'],
        ],
    },
    ru: {
        dir: 'ru-RU',
        switchFrom: null, // ru is the default locale, nothing to switch
        switchTo: null,
        save: 'Сохранить',
        back: 'Назад',
        name: 'Название',
        description: 'Описание',
        newProject: 'Новое',
        fromType: 'Прямоугольный шарф',
        toType: 'Треугольный палантин',
        projects: [
            ['Шарф для мамы', 'Пряжа Alize Lanagold, спицы 3.5, резинка 2×2'],
            ['Палантин из мохера', 'Кид-мохер в две нити, спицы 4'],
        ],
    },
} as const;

type Locale = keyof typeof locales;

const requested = Bun.argv.slice(2).filter((a) => !a.startsWith('-'));
for (const id of requested) {
    if (!(id in locales)) {
        throw new Error(`unknown locale "${id}", expected en or ru`);
    }
}
const wanted = (
    requested.length ? requested : Object.keys(locales)
) as Locale[];

const metadataPath = 'packaging/metadata/metadata.yaml';
const metadata = Bun.YAML.parse(await readFile(metadataPath, 'utf8')) as {
    urls: { website: string };
};
// The published build is the subject, so its address comes from the same single
// source every listing is rendered from rather than being spelled again here.
const appUrl = Bun.env.APP_URL ?? metadata.urls.website;
const outRoot = Bun.env.OUT_ROOT ?? 'packaging/metadata/screenshots';

/// The browser to drive. Chrome and Chromium both work; the name differs per
/// distribution, so the first one on PATH wins unless CHROME says otherwise.
const chromePath =
    Bun.env.CHROME ??
    Bun.which('google-chrome-stable') ??
    Bun.which('google-chrome') ??
    Bun.which('chromium') ??
    Bun.which('chromium-browser');
if (!chromePath) {
    throw new Error('no Chrome or Chromium on PATH; set CHROME to one');
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/// Drives one locale from a cold profile and leaves three PNGs behind.
async function capture(id: Locale) {
    const l = locales[id];
    const out = join(outRoot, l.dir, 'phone');
    const profile = await mkdtemp(join(tmpdir(), `knitcalc-shots-${id}-`));

    const chrome = Bun.spawn(
        [
            chromePath!,
            '--headless=new',
            // Port 0 lets Chrome pick a free one and write it to
            // DevToolsActivePort, so two runs never collide.
            '--remote-debugging-port=0',
            '--hide-scrollbars',
            '--no-first-run',
            '--no-default-browser-check',
            // Policy-installed extensions open their own onboarding tabs, and
            // Page.captureScreenshot never returns for a backgrounded tab.
            '--disable-extensions',
            `--user-data-dir=${profile}`,
            'about:blank',
        ],
        { stdout: 'ignore', stderr: 'ignore' },
    );

    let port = 0;
    for (let i = 0; i < 100 && !port; i++) {
        await sleep(200);
        const file = Bun.file(join(profile, 'DevToolsActivePort'));
        if (await file.exists()) {
            port = Number((await file.text()).split('\n')[0]);
        }
    }
    if (!port) throw new Error('Chrome never wrote DevToolsActivePort');

    let wsUrl = '';
    for (let i = 0; i < 50 && !wsUrl; i++) {
        try {
            const res = await fetch(`http://127.0.0.1:${port}/json/list`);
            const targets = (await res.json()) as Array<{
                type: string;
                webSocketDebuggerUrl: string;
            }>;
            wsUrl =
                targets.find((t) => t.type === 'page')?.webSocketDebuggerUrl ??
                '';
        } catch {
            /* not up yet */
        }
        if (!wsUrl) await sleep(200);
    }
    if (!wsUrl) throw new Error('CDP endpoint never came up');

    const ws = new WebSocket(wsUrl);
    await new Promise((r) => (ws.onopen = r));

    let nextId = 1;
    const pending = new Map<number, (v: unknown) => void>();
    ws.onmessage = (e) => {
        const msg = JSON.parse(String(e.data));
        if (msg.id && pending.has(msg.id)) {
            pending.get(msg.id)!(msg.result ?? msg.error);
            pending.delete(msg.id);
        }
    };
    const send = (method: string, params: Record<string, unknown> = {}) =>
        // CDP replies are free-form JSON; every caller below reads one known
        // field out of them.
        new Promise<any>((resolve) => {
            const msgId = nextId++;
            pending.set(msgId, resolve as (v: unknown) => void);
            ws.send(JSON.stringify({ id: msgId, method, params }));
        });
    const evaluate = async (expression: string) => {
        const r = await send('Runtime.evaluate', {
            expression,
            awaitPromise: true,
            returnByValue: true,
        });
        return r?.result?.value;
    };

    const shoot = async (name: string) => {
        const r = await send('Page.captureScreenshot', {
            format: 'png',
            captureBeyondViewport: false,
        });
        const path = join(out, `${name}.png`);
        await Bun.write(path, Buffer.from(r.data, 'base64'));
        console.log(`wrote ${path}`);
    };
    const tap = async (x: number, y: number) => {
        for (const type of ['mousePressed', 'mouseReleased'] as const) {
            await send('Input.dispatchMouseEvent', {
                type,
                x,
                y,
                button: 'left',
                clickCount: 1,
            });
        }
        await sleep(300);
    };
    /// Building the semantics tree is what makes any of the above addressable;
    /// it also has to be rebuilt after every overlay (see `tapOverlay`).
    const enableSemantics = async () => {
        await evaluate(
            `document.querySelector('flt-semantics-placeholder')?.click(), 1`,
        );
        await sleep(1500);
    };
    type Box = { x: number; y: number; w: number; h: number };
    /// Every semantics node containing `text`, so a caller can tell the app
    /// bar's action from the identically labelled dialog button by position.
    const boxesOf = async (selector: string, text: string): Promise<Box[]> =>
        (await evaluate(`(() => {
          return [...document.querySelectorAll(${JSON.stringify(selector)})]
            .filter(e => (e.textContent || '')
                .includes(${JSON.stringify(text)}))
            .map(e => {
                const r = e.getBoundingClientRect();
                return {
                    x: r.left + r.width / 2, y: r.top + r.height / 2,
                    w: r.width, h: r.height,
                };
            })
            .filter(b => b.w > 0 && b.h > 0);
        })()`)) ?? [];
    const tapButton = async (
        text: string,
        pick: (boxes: Box[]) => Box = (boxes) => boxes[0]!,
    ) => {
        for (let attempt = 0; attempt < 5; attempt++) {
            const boxes = await boxesOf('flt-semantics[role=button]', text);
            if (boxes.length) {
                const b = pick(boxes);
                await tap(b.x, b.y);
                return;
            }
            await sleep(600);
        }
        throw new Error(`no button labelled "${text}"`);
    };
    /// The lowest match, which is how the save dialog's own Save is told apart
    /// from the app bar's action of the same name.
    const lowest = (boxes: Box[]) =>
        boxes.reduce((a, b) => (b.y > a.y ? b : a));
    /// Asserts that `text` is on screen. Both coordinate taps below are checked
    /// this way: a missed one would otherwise be noticed only as a Russian
    /// screenshot in the English directory, or as two rectangular scarves.
    const expect = async (text: string, complaint: string) => {
        if (!(await boxesOf('flt-semantics', text)).length) {
            throw new Error(complaint);
        }
    };
    /// An open PopupMenuButton or Dropdown empties the whole semantics tree —
    /// measured: every flt-semantics node disappears while the route is up and
    /// does not come back — so entries in those overlays are tapped where they
    /// always sit and the tree is rebuilt afterwards. Plain dialogs keep their
    /// semantics and are driven through `tapButton` as usual.
    const tapOverlay = async (x: number, y: number) => {
        await sleep(1500);
        await tap(x, y);
        await sleep(2000);
        await enableSemantics();
    };
    /// Fills the calculator's fields in DOM order; Flutter mirrors each of them
    /// into an <input>, but only while the field is the focused one, so they
    /// have to be tapped one by one.
    const fillFields = async (values: string[]) => {
        for (let i = 0; i < values.length; i++) {
            const box = await evaluate(`(() => {
              const el = [...document.querySelectorAll('input')][${i}];
              if (!el) return null;
              const r = el.getBoundingClientRect();
              return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
            })()`);
            if (!box) throw new Error(`no input #${i} to fill`);
            await tap(box.x, box.y);
            await send('Input.insertText', { text: values[i] });
            await sleep(150);
        }
    };
    const typeInto = async (label: string, text: string) => {
        const box = await evaluate(`(() => {
          const el = [...document.querySelectorAll('input, textarea')]
            .find(i => i.getAttribute('aria-label')
                === ${JSON.stringify(label)});
          if (!el) return null;
          const r = el.getBoundingClientRect();
          return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
        })()`);
        if (!box) throw new Error(`no field labelled "${label}"`);
        await tap(box.x, box.y);
        await send('Input.insertText', { text });
        await sleep(250);
    };
    const scrollBy = async (dy: number) => {
        await send('Input.dispatchMouseEvent', {
            type: 'mouseWheel',
            x: 216,
            y: 500,
            deltaX: 0,
            deltaY: dy,
            button: 'none',
        });
        await sleep(1200);
    };
    /// Opens the save dialog and fills it in, leaving it on screen: the second
    /// screenshot is taken between this and `confirmSave`.
    const openSaveDialog = async ([title, note]: readonly string[]) => {
        await tapButton(l.save); // the app bar's save action
        await sleep(1800);
        await typeInto(l.name, title!);
        await typeInto(l.description, note!);
        await sleep(800);
    };
    const confirmSave = async () => {
        await tapButton(l.save, lowest);
        await sleep(2500);
    };

    await send('Page.enable');
    await send('Runtime.enable');
    // 432x768 at scale 2.5 is 1080x1920 and fits far more of the form than
    // 360x640 at 3 does.
    await send('Emulation.setDeviceMetricsOverride', {
        width: 432,
        height: 768,
        deviceScaleFactor: 2.5,
        mobile: true,
        screenOrientation: { type: 'portraitPrimary', angle: 0 },
    });
    await send('Page.bringToFront');
    await send('Page.navigate', { url: appUrl });
    await sleep(9000);
    await enableSemantics();

    if (l.switchFrom && l.switchTo) {
        await tapButton(l.switchFrom);
        // English is the first entry of the language popup, just below the app
        // bar.
        await tapOverlay(295, 40);
        await expect(l.switchTo, `language did not switch to ${l.switchTo}`);
    }

    // The first project: a scarf, shot with its results and then with the save
    // dialog over them. It has nine inputs; the last (the swatch yarn's width)
    // is left empty on purpose — none of the results on screen need it.
    await fillFields(['44', '20', '60', '20', '55', '170', '30', '350']);
    await scrollBy(2000);
    await shoot('calculator');
    await openSaveDialog(l.projects[0]);
    await shoot('project');
    await confirmSave();

    // The second project: a shawl, so the list has more than one row. Its type
    // is the dropdown's second entry, right under the first, and it asks for
    // three measurements after the gauge where the scarf asks for five.
    await tapButton(l.newProject);
    await sleep(2500);
    await tapButton(l.fromType);
    await tapOverlay(150, 151);
    await expect(l.toType, `item type is not "${l.toType}"`);
    await fillFields(['38', '15', '52', '15', '120', '60', '150']);
    await sleep(800);
    await openSaveDialog(l.projects[1]);
    await confirmSave();

    // Saving it leaves us on that project's own screen, since it was opened
    // from the list.
    await tapButton(l.back);
    await sleep(2500);
    // Let the "saved" snackbar fade before the list shot.
    await sleep(6000);
    await shoot('projects');

    ws.close();
    chrome.kill();
    await chrome.exited;
    await rm(profile, { recursive: true, force: true });
}

for (const id of wanted) {
    console.log(`capturing ${id} (${locales[id].dir}) from ${appUrl}`);
    await capture(id);
}
console.log(`captured ${shots.join(', ')} for ${wanted.join(', ')}`);
