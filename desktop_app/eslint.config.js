import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: ["dist/"],
  },
  tseslint.configs.recommended,
  {
    rules: {
      "no-unused-vars": "warn",
      "@typescript-eslint/no-unused-vars": "off",
    },
  }
);
