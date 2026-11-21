// Render each art/ears/*.svg to a transparent PNG with Chromium (Playwright).
// Usage: node scripts/render-ears.js <svg dir> <out dir> <size>
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

(async () => {
	const [srcDir, outDir, sizeArg] = process.argv.slice(2);
	const size = Number(sizeArg);
	fs.mkdirSync(outDir, { recursive: true });
	const browser = await chromium.launch();
	const page = await browser.newPage({ viewport: { width: size, height: size } });
	for (const file of fs.readdirSync(srcDir).filter((f) => f.endsWith(".svg")).sort()) {
		const svg = fs.readFileSync(path.join(srcDir, file)).toString("base64");
		await page.setContent(
			`<html><body style="margin:0;background:transparent">` +
				`<img src="data:image/svg+xml;base64,${svg}" width="${size}" height="${size}"></body></html>`,
		);
		await page.waitForLoadState("load");
		await page.screenshot({
			path: path.join(outDir, file.replace(/\.svg$/, ".png")),
			omitBackground: true,
			clip: { x: 0, y: 0, width: size, height: size },
		});
	}
	await browser.close();
})().catch((err) => {
	console.error(err);
	process.exit(1);
});
