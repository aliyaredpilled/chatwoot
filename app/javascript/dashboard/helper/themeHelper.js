import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

export const setColorTheme = isOSOnDarkMode => {
  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';

  // Remove all theme classes first
  document.body.classList.remove('dark', 'cafe');

  if (selectedColorScheme === 'cafe') {
    document.body.classList.add('cafe');
    document.documentElement.style.setProperty('color-scheme', 'light');
  } else if (
    (selectedColorScheme === 'auto' && isOSOnDarkMode) ||
    selectedColorScheme === 'dark'
  ) {
    document.body.classList.add('dark');
    document.documentElement.style.setProperty('color-scheme', 'dark');
  } else {
    document.documentElement.style.setProperty('color-scheme', 'light');
  }
};
