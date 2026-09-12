import { chromium } from '@playwright/test'
import fs from 'fs'
import path from 'path'

const TARGET_URL = process.env.TARGET_URL || 'https://astraflow.scloudsg.com'
const OUTPUT_FILE = path.resolve(process.cwd(), 'astraflow_cookies.json')
const USER_DATA_DIR = path.resolve(process.cwd(), '.playwright_astraflow_session')

async function main() {
  const headless = process.env.HEADLESS !== 'false'
  console.log(`Khoi chay Playwright su dung Chrome he thong (/usr/bin/google-chrome, headless=${headless})...`)
  console.log(`Muc tieu: ${TARGET_URL}`)

  const context = await chromium.launchPersistentContext(USER_DATA_DIR, {
    executablePath: '/usr/bin/google-chrome',
    headless,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  })

  const page = context.pages().length > 0 ? context.pages()[0] : await context.newPage()

  try {
    console.log(`Dang truy cap vao ${TARGET_URL}...`)
    await page.goto(TARGET_URL, { waitUntil: 'networkidle', timeout: 45000 })

    const currentUrl = page.url()
    const pageTitle = await page.title()
    console.log(`Trang hien tai: ${currentUrl} | Tieu de: ${pageTitle}`)

    const cookies = await context.cookies()
    console.log(`Thu thap duoc ${cookies.length} cookie(s).`)

    const result = {
      targetUrl: TARGET_URL,
      finalUrl: currentUrl,
      title: pageTitle,
      extractedAt: new Date().toISOString(),
      cookieCount: cookies.length,
      cookieHeader: cookies.map((c) => `${c.name}=${c.value}`).join('; '),
      cookies,
    }

    fs.writeFileSync(OUTPUT_FILE, JSON.stringify(result, null, 2), 'utf-8')
    console.log(`Xuat file thanh cong tai: ${OUTPUT_FILE}`)
    console.log(`Chuoi Cookie Header de goi API:\n${result.cookieHeader}`)
  } catch (err) {
    console.error('Loi trong qua trinh thu thap cookie:', err)
  } finally {
    await context.close()
  }
}

main()
