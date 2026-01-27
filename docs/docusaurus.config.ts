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
        docs: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],
  plugins: [
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'routed',
        path: 'docs/routed',
        routeBasePath: 'docs/routed',
        sidebarPath: './sidebars/routed.ts',
        editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'routed_hotwire',
        path: 'docs/routed_hotwire',
        routeBasePath: 'docs/routed_hotwire',
        sidebarPath: './sidebars/routed_hotwire.ts',
        editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'routed_inertia',
        path: 'docs/routed_inertia',
        routeBasePath: 'docs/routed_inertia',
        sidebarPath: './sidebars/routed_inertia.ts',
        editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'server_testing',
        path: 'docs/server-testing',
        routeBasePath: 'docs/server_testing',
        sidebarPath: './sidebars/server_testing.ts',
        editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'server_testing_shelf',
        path: 'docs/server_testing_shelf',
        routeBasePath: 'docs/server_testing_shelf',
        sidebarPath: './sidebars/server_testing_shelf.ts',
        editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'routed_testing',
        path: 'docs/routed_testing',
        routeBasePath: 'docs/routed_testing',
        sidebarPath: './sidebars/routed_testing.ts',
        editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
      },
    ],
    [
      '@docusaurus/plugin-content-docs',
      {
        id: 'property_testing',
        path: 'docs/property-testing',
        routeBasePath: 'docs/property_testing',
        sidebarPath: './sidebars/property_testing.ts',
        editUrl: 'https://github.com/kingwill101/routed/tree/main/docs/',
      },
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
          sidebarId: 'routedSidebar',
          docsPluginId: 'routed',
          position: 'left',
          label: 'Routed',
        },
        {
          type: 'docSidebar',
          sidebarId: 'routedHotwireSidebar',
          docsPluginId: 'routed_hotwire',
          position: 'left',
          label: 'Routed Hotwire',
        },
        {
          type: 'docSidebar',
          sidebarId: 'serverTestingSidebar',
          docsPluginId: 'server_testing',
          position: 'left',
          label: 'Server Testing',
        },
        {
          type: 'docSidebar',
          sidebarId: 'serverTestingShelfSidebar',
          docsPluginId: 'server_testing_shelf',
          position: 'left',
          label: 'Server Testing Shelf',
        },
        {
          type: 'docSidebar',
          sidebarId: 'routedTestingSidebar',
          docsPluginId: 'routed_testing',
          position: 'left',
          label: 'Routed Testing',
        },
        {
          type: 'docSidebar',
          sidebarId: 'propertyTestingSidebar',
          docsPluginId: 'property_testing',
          position: 'left',
          label: 'Property Testing',
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
            {label: 'Routed', to: '/docs/routed/'},
            {label: 'Routed Hotwire', to: '/docs/routed_hotwire/'},
            {label: 'Server Testing', to: '/docs/server_testing/'},
            {label: 'Server Testing Shelf', to: '/docs/server_testing_shelf/'},
            {label: 'Routed Testing', to: '/docs/routed_testing/'},
            {label: 'Property Testing', to: '/docs/property_testing/'},
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
