import { Platform } from 'react-native';

/**
 * The monospace family to use for packet output, tables and terminal views.
 *
 * A CSS font stack like '"Courier New", Courier, monospace' only works on web.
 * React Native passes fontFamily straight to the platform as a single family
 * name, so on iOS that string matches nothing and silently falls back to the
 * system font - which is proportional, so columns stop lining up. It is not an
 * error, just the wrong glyphs, which is why it looked fine in the browser.
 *
 * Menlo ships with iOS and is the same family Terminal.app uses. Android has
 * no Courier, but resolves the generic 'monospace' to Droid Sans Mono.
 */
export const MONO_FONT = Platform.select({
    ios: 'Menlo',
    android: 'monospace',
    default: '"Courier New", Courier, monospace',
});
