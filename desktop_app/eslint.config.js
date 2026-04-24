import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: ["dist/", "src-tauri/target/"],
  },
  tseslint.configs.recommended,
  {
    rules: {
      "no-unused-vars": "off",
      "@typescript-eslint/no-unused-vars": [
        "warn",
        {
          argsIgnorePattern: "^_",
        },
      ],
    },
  }
);
