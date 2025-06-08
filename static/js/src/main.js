import { createApp } from 'vue';
import App from './App.vue';

// Since style.css is global, ensure it's linked in index.html
// If you had component-specific styles that were previously in style.css and are now in App.vue <style scoped>,
// they will be handled by vue-loader.

createApp(App).mount('#app'); 