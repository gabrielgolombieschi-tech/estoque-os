import { test } from "@playwright/test";

test("diagnostico /os", async ({ page }) => {
  test.setTimeout(120_000);
  page.on("console", (m) => console.log(`[console:${m.type()}] ${m.text()}`));
  page.on("pageerror", (e) => console.log(`[pageerror] ${e.message}`));
  page.on("requestfailed", (r) => console.log(`[reqfail] ${r.url()} :: ${r.failure()?.errorText}`));
  page.on("response", (r) => {
    if (r.status() >= 400) console.log(`[http ${r.status()}] ${r.url()}`);
  });

  await page.goto("/os");
  await page.waitForTimeout(15_000);
  console.log("URL FINAL:", page.url());
  const html = await page.locator("body").innerHTML();
  console.log("BODY LEN:", html.length);
  console.log("BODY:", html.slice(0, 3000));
});
