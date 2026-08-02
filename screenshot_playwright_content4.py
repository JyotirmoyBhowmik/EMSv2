from playwright.sync_api import sync_playwright

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        page.goto('http://localhost:3000')

        page.evaluate("sessionStorage.setItem('auth_token', 'dummy_token')")
        page.evaluate("sessionStorage.setItem('display_role', 'admin')")

        page.goto('http://localhost:3000/dashboard')
        page.wait_for_timeout(2000)
        print(page.content())
        browser.close()

if __name__ == '__main__':
    run()
