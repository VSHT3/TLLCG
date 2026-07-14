import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";

export default defineConfig({
	plugins: [react()],
	resolve: {
		alias: {
			"@data": fileURLToPath(new URL("../data", import.meta.url)),
			"@engine": fileURLToPath(new URL("./src/engine", import.meta.url)),
		},
	},
	test: {
		include: ["test/**/*.test.ts"],
		environment: "node",
	},
});
