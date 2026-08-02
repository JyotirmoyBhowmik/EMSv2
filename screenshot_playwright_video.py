from playwright.sync_api import sync_playwright
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context(record_video_dir="videos/")
        page = context.new_page()

        page.goto('http://localhost:3000')

        page.evaluate("sessionStorage.setItem('auth_token', 'dummy_token')")
        page.evaluate("sessionStorage.setItem('user', JSON.stringify({ role: 'admin' }))")
        page.goto('http://localhost:3000/dashboard')
        time.sleep(2)

        page.goto('http://localhost:3000/results')
        time.sleep(1)

        page.goto('http://localhost:3000/scan')
        time.sleep(1)

        page.goto('http://localhost:3000/admin/users')
        time.sleep(1)

        context.close()
        browser.close()

if __name__ == '__main__':
    run()
