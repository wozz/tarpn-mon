import React from 'react';
import { Platform, Text, View } from 'react-native';

/**
 * Cross-platform wrapper for components that use Skia (e.g., victory-native charts).
 * On web, Skia needs to load CanvasKit WASM before rendering, AND victory-native
 * must be dynamically imported (its module evaluation captures global.CanvasKit).
 * On native, components render directly.
 *
 * Usage: <SkiaChart style={...}>{(VN) => <VN.CartesianChart ... />}</SkiaChart>
 * The render function receives the victory-native module exports.
 */
export function SkiaChart({ children, fallback, style }) {
  if (Platform.OS === 'web') {
    return <SkiaWebChart fallback={fallback} style={style}>{children}</SkiaWebChart>;
  }
  // On native, victory-native is statically imported and CanvasKit isn't needed
  return <SkiaNativeChart fallback={fallback} style={style}>{children}</SkiaNativeChart>;
}

// Native: load victory-native once, pass to render function
// Note: victory-native requires @shopify/react-native-skia which needs custom native code.
// This won't work in Expo Go — only in development builds or standalone apps.
function SkiaNativeChart({ children, fallback, style }) {
  const [vn, setVN] = React.useState(null);
  const [error, setError] = React.useState(null);

  React.useEffect(() => {
    let cancelled = false;
    import('victory-native').then(mod => {
      if (cancelled) return;
      // Validate the module loaded correctly — if Skia/reanimated aren't available,
      // the import may resolve but exports may be undefined
      if (!mod || !mod.CartesianChart) {
        setError(new Error('victory-native loaded but exports are missing (Skia unavailable)'));
        return;
      }
      setVN(mod);
    }).catch(e => {
      console.warn('Failed to load victory-native (Skia not available in Expo Go):', e.message);
      if (!cancelled) setError(e);
    });
    return () => { cancelled = true; };
  }, []);

  if (error) {
    return <View style={style}><Text style={{ color: '#777' }}>Charts require a development build (not available in Expo Go)</Text></View>;
  }
  if (!vn) {
    return fallback || <View style={style}><Text style={{ color: '#555' }}>Loading charts...</Text></View>;
  }
  return <View style={style}>{typeof children === 'function' ? children(vn) : children}</View>;
}

// Web-specific: loads CanvasKit WASM first, then dynamically imports victory-native
function SkiaWebChart({ children, fallback, style }) {
  const [vn, setVN] = React.useState(null);
  const [error, setError] = React.useState(null);

  React.useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        // 1. Load CanvasKit WASM and set global.CanvasKit
        const { LoadSkiaWeb } = await import('@shopify/react-native-skia/lib/module/web');
        await LoadSkiaWeb({
          locateFile: (file) => `/${file}`,
        });
        // 2. Now safe to import victory-native (its module init reads global.CanvasKit)
        const mod = await import('victory-native');
        if (!cancelled) setVN(mod);
      } catch (e) {
        console.warn('Failed to load Skia for web:', e);
        if (!cancelled) setError(e);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  if (error) {
    return <View style={style}><Text style={{ color: '#777' }}>Charts unavailable</Text></View>;
  }
  if (!vn) {
    return fallback || <View style={style}><Text style={{ color: '#555' }}>Loading charts...</Text></View>;
  }
  return <View style={style}>{typeof children === 'function' ? children(vn) : children}</View>;
}
