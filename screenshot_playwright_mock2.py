from playwright.sync_api import sync_playwright
import time
import json

def handle_route(route):
    # Mock any API request to return success
    # Some common responses
    if "api/auth/providers" in route.request.url:
        route.fulfill(status=200, content_type="application/json", body=json.dumps([]))
    elif "api/dashboard/stats" in route.request.url:
        route.fulfill(status=200, content_type="application/json", body=json.dumps({"totalEndpoints": 10, "activeAlerts": 2}))
    else:
        route.fulfill(status=200, content_type="application/json", body=json.dumps({"data": []}))

def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(record_video_dir="videos_mocked/")
        page = context.new_page()

        page.route("**/api/**", handle_route)

        page.goto('http://localhost:3000')

        # In Playwright, sessionStorage set must match the domain exactly. Wait for DOM ready or do it via init script
        page.evaluate("sessionStorage.setItem('auth_token', 'dummy_token')")
        page.evaluate("sessionStorage.setItem('user', JSON.stringify({ role: 'GlobalAdmin' }))") # Changed to GlobalAdmin since it uses this role sometimes

        # force reload to apply token
        page.reload()
        page.goto('http://localhost:3000/dashboard')
        page.wait_for_selector('nav', timeout=10000)
        time.sleep(2)
        page.screenshot(path='dashboard.png')

        page.goto('http://localhost:3000/results')
        time.sleep(2)
        page.screenshot(path='results.png')

        page.goto('http://localhost:3000/scan')
        time.sleep(2)
        page.screenshot(path='scan.png')

        page.goto('http://localhost:3000/admin/users')
        time.sleep(2)
        page.screenshot(path='admin_users.png')

        context.close()
        browser.close()

if __name__ == '__main__':
    run()
