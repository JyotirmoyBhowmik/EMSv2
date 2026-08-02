from playwright.sync_api import sync_playwright
import time

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page()

        # Navigate to home
        page.goto('http://localhost:3000')

        # We might be redirected to /login, let's inject a session first and mock user role
        # We need to bypass the login requirement.
        page.evaluate("sessionStorage.setItem('auth_token', 'dummy_token')")
        page.evaluate("sessionStorage.setItem('user', JSON.stringify({ role: 'admin' }))")
        page.goto('http://localhost:3000/dashboard')
        time.sleep(2)

        page.screenshot(path='dashboard.png')

        page.goto('http://localhost:3000/results')
        time.sleep(1)
        page.screenshot(path='results.png')

        page.goto('http://localhost:3000/scan')
        time.sleep(1)
        page.screenshot(path='scan.png')

        page.goto('http://localhost:3000/admin/users')
        time.sleep(1)
        page.screenshot(path='admin_users.png')

        browser.close()

if __name__ == '__main__':
    run()
