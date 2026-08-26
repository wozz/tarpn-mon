import js from '@eslint/js';
import globals from 'globals';
import reactPlugin from 'eslint-plugin-react';
import reactHooksPlugin from 'eslint-plugin-react-hooks';

export default [
  js.configs.recommended,
  {
    files: ['**/*.js', '**/*.jsx'],
    plugins: {
      react: reactPlugin,
      'react-hooks': reactHooksPlugin,
    },
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        ...globals.browser,
        ...globals.node,
        ...globals.es2021,
      },
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
      },
    },
    settings: {
      react: {
        version: 'detect',
      },
    },
    rules: {
      // React rules
      'react/jsx-uses-react': 'error',
      'react/jsx-uses-vars': 'error',
      'react/prop-types': 'off', // Not using PropTypes
      'react/react-in-jsx-scope': 'off', // Not needed in React 17+

      // React Hooks rules
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',

      // General rules

      // Catches reading a const/let above its declaration. That is a runtime
      // ReferenceError from the temporal dead zone, and nothing else here
      // finds it: Metro bundles it happily, the export succeeds, and no test
      // mounts a screen. It shipped once as a blank page with "Cannot access
      // uninitialized variable" - a dependency array referencing a const
      // declared further down, which is evaluated during render.
      //
      // functions: false because function declarations hoist, and calling one
      // defined lower in the file is both legal and common here.
      //
      // variables: false ignores a reference whose declaration is in an outer
      // scope, which is the React Native convention of putting
      // StyleSheet.create at the foot of the file - safe, because the module
      // finishes evaluating before any component renders. Same-scope
      // use-before-declaration, which is the bug above, is still an error.
      'no-use-before-define': ['error', { functions: false, classes: true, variables: false }],
      'no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      'no-console': 'off', // Allow console for debugging
    },
  },
  // Jest test files
  {
    files: ['**/*.test.js', '**/*.spec.js'],
    languageOptions: {
      globals: {
        ...globals.jest,
        describe: 'readonly',
        it: 'readonly',
        expect: 'readonly',
        beforeEach: 'readonly',
        afterEach: 'readonly',
        beforeAll: 'readonly',
        afterAll: 'readonly',
        jest: 'readonly',
      },
    },
  },
  {
    ignores: [
      'node_modules/**',
      '.expo/**',
      'dist/**',
      'web-build/**',
    ],
  },
];
