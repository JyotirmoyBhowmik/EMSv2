from playwright.sync_api import sync_playwright

def run_cuj(page):
    page.goto("http://localhost:3000")
    page.wait_for_timeout(1000)

    # Bypass auth and load the user management page
    page.evaluate("sessionStorage.setItem('auth_token', 'dummy_token')")
    page.evaluate("sessionStorage.setItem('display_role', 'admin')")
    page.goto("http://localhost:3000/admin/users")
    page.wait_for_timeout(1000)

    # 1. Click Create User button
    page.get_by_role("button", name="+ Create User").click()
    page.wait_for_timeout(1000)

    # We mock the API call so it takes a bit of time to resolve, simulating the loading state
    def handle_route(route):
        import time
        time.sleep(2) # 2s delay
        route.fulfill(json={"message": "success"})

    page.route("**/api/admin/users", handle_route)

    # 2. Fill the form
    page.get_by_label("username").fill("testuser")
    page.wait_for_timeout(500)
    page.get_by_label("email").fill("testuser@example.com")
    page.wait_for_timeout(500)

    # 3. Click Save button
    page.get_by_role("button", name="Save").click()

    # Immediately capture the "Saving..." state screenshot
    page.screenshot(path="/home/jules/verification/screenshots/verification.png")
    page.wait_for_timeout(2500) # wait for mock to finish


if __name__ == "__main__":
    import os
    os.makedirs("/home/jules/verification/screenshots", exist_ok=True)
    os.makedirs("/home/jules/verification/videos", exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            record_video_dir="/home/jules/verification/videos"
        )
        page = context.new_page()
        try:
            run_cuj(page)
        finally:
            context.close()
            browser.close()
