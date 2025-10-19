import {themes as prismThemes} from 'prism-react-renderer';
import type {Config} from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

// This runs in Node.js - Don't use client-side code here (browser APIs, JSX...)

const config: Config = {
  title: 'Routed',
    tagline: 'Routing, testing, and property-based tooling for Dart',
  favicon: 'img/favicon.ico',

  // Set the production url of your site here
    url: 'https://kingwill101.github.io',
  // Set the /<baseUrl>/ pathname under which your site is served
  // For GitHub pages deployment, it is often '/<projectName>/'
  baseUrl: '/',

  // GitHub pages deployment config.
  // If you aren't using GitHub pages, you don't need these.
    organizationName: 'kingwill101', // GitHub org/user name.
    projectName: 'routed', // Repo name.

  onBrokenLinks: 'throw',

    markdown: {
        hooks: {
            onBrokenMarkdownLinks: 'warn',
        },
    },

  // Even if you don't use internationalization, you can use this field to set
  // useful metadata like html lang. For example, if your site is Chinese, you
  // may want to replace "en" with "zh-Hans".
  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      {
        docs: {
          sidebarPath: './sidebars.ts',
            editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
        },
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  themeConfig: {
    // Replace with your project's social card
    image: 'img/docusaurus-social-card.jpg',
    navbar: {
      title: 'Routed',
      logo: {
        alt: 'Routed Logo',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'tutorialSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
            href: 'https://github.com/kingwill101/routed',
          label: 'GitHub',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
              {label: 'Server Testing', to: '/docs/server-testing/'},
              {label: 'Property Testing', to: '/docs/property-testing/'},
              {label: 'Routed', to: '/docs/routed/'},
          ],
        },
        {
            title: 'Project',
          items: [
              {label: 'GitHub', href: 'https://github.com/kingwill101/routed'},
            {
                label: 'Issue Tracker',
                href: 'https://github.com/kingwill101/routed/issues',
            },
          ],
        },
      ],
        copyright: `Copyright © ${new Date().getFullYear()} Routed contributors.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
        additionalLanguages: ['dart'],
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
