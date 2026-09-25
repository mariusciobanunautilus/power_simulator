import { defineConfig } from "@playwright/test";

const mockEnv = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54329",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "test-publishable-key",
  NEXT_PUBLIC_SITE_URL: "http://localhost:3100",
};

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  workers: 1,
  use: {
    baseURL: "http://localhost:3100",
    headless: true,
    launchOptions: {
      executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,
    },
    trace: "retain-on-failure",
  },
  webServer: [
    {
      command: "node tests/mock-supabase.mjs",
      port: 54329,
      reuseExistingServer: false,
    },
    {
      command: "npm run dev -- --port 3100 --hostname 127.0.0.1",
      port: 3100,
      reuseExistingServer: false,
      env: mockEnv,
    },
  ],
});
