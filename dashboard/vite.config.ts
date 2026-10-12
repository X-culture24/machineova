import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, ".", "");
  return {
    plugins: [react()],
    server: {
      port: 5173,
      // Dev proxy so the dashboard talks to the Go API without CORS.
      proxy: { "/api": env.API_URL || "http://localhost:8080" },
    },
  };
});
