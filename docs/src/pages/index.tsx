import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';

import styles from './index.module.css';

const highlightCards = [
  {
    title: 'Plain HttpServer',
    description:
      'Start with raw dart:io and the Inertia protocol helpers when you want the smallest possible stack.',
  },
  {
    title: 'Framework Adapters',
    description:
      'Use adapter packages when you want shared defaults, request helpers, and tighter framework integration.',
  },
  {
    title: 'SSR Ready',
    description:
      'Use the same asset and page helpers in client-only and SSR setups, then point them at a standard Inertia renderer.',
  },
];

const quickLinks = [
  {label: 'Core Reference', to: '/docs/'},
  {label: 'HttpServer Guide', to: '/docs/httpserver'},
  {label: 'Serinus Guide', to: '/docs/serinus'},
  {label: 'Routed Adapter', to: '/docs/routed/'},
  {label: 'Contacts Tutorial', to: '/docs/tutorial'},
  {label: 'Routed Tutorial', to: '/docs/routed/tutorial'},
];

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
        <Heading as="h1" className={styles.heroTitle}>
          Build server-driven apps with Inertia and Dart
        </Heading>
        <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
        <div className={styles.buttons}>
          <Link className="button button--secondary button--lg" to="/docs/">
            Read the core docs
          </Link>
          <Link className="button button--secondary button--lg" to="/docs/httpserver">
            Start with HttpServer
          </Link>
          <Link className="button button--secondary button--lg" to="/docs/serinus">
            Use Serinus
          </Link>
          <Link className="button button--secondary button--lg" to="/docs/routed/">
            Use Routed
          </Link>
          <a className="button button--primary button--lg" href="https://github.com/kingwill101/routed">
            GitHub Repository
          </a>
        </div>
      </div>
    </header>
  );
}

function QuickStartSection() {
  return (
    <section className={styles.quickStart}>
      <div className="container">
        <div className="row">
          <div className="col col--5">
            <Heading as="h2">Install the pieces you need</Heading>
            <p>
              Start with the core package for the Inertia protocol and add an adapter
              only when you want framework-specific ergonomics.
            </p>
          </div>
          <div className="col col--7">
            <CodeBlock language="bash">
              {`# Core protocol helpers
dart pub add inertia_dart

# Routed adapter
dart pub add routed_inertia

# Serinus adapter
dart pub add serinus_inertia`}
            </CodeBlock>
          </div>
        </div>
      </div>
    </section>
  );
}

function PackagesTable() {
  return (
    <section className={styles.packageTable}>
      <div className="container">
        <Heading as="h2">Packages at a glance</Heading>
        <div className="table-responsive">
          <table>
            <thead>
              <tr>
                <th>Package</th>
                <th>What it does</th>
                <th>Start with</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><code>inertia_dart</code></td>
                <td>Core protocol helpers, Vite assets, SSR gateway, testing utilities</td>
                <td><Link to="/docs/">Core docs</Link></td>
              </tr>
              <tr>
                <td><code>serinus_inertia</code></td>
                <td>Serinus module integration, request helpers, app-wide Inertia defaults</td>
                <td><Link to="/docs/serinus">Serinus guide</Link></td>
              </tr>
              <tr>
                <td><code>routed_inertia</code></td>
                <td>Routed middleware, template helpers, config-driven SSR and assets</td>
                <td><Link to="/docs/routed/">Routed docs</Link></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}

function HighlightsSection() {
  return (
    <section className={styles.highlights}>
      <div className="container">
        <Heading as="h2" className={styles.sectionTitle}>
          One protocol, multiple server styles
        </Heading>
        <div className="row">
          {highlightCards.map((item) => (
            <div key={item.title} className="col col--4">
              <div className={clsx('card', styles.highlightCard)}>
                <div className="card__header">
                  <Heading as="h3">{item.title}</Heading>
                </div>
                <div className="card__body">
                  <p>{item.description}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function QuickLinks() {
  return (
    <section className={styles.quickLinks}>
      <div className="container">
        <Heading as="h2" className={styles.sectionTitle}>
          Jump right in
        </Heading>
        <div className="row">
          {quickLinks.map((item) => (
            <div key={item.label} className="col col--4 padding-horiz--sm padding-vert--sm">
              <Link className={clsx('card', styles.quickLinkCard)} to={item.to}>
                <div className="card__body">
                  <Heading as="h4" style={{marginBottom: '0.5rem'}}>
                    {item.label}
                  </Heading>
                  <span
                    style={{
                      fontSize: '0.85rem',
                      color: 'var(--ifm-color-primary)',
                    }}>
                    Read more →
                  </span>
                </div>
              </Link>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();

  return (
    <Layout
      title={siteConfig.title}
      description="Inertia.js server adapters and setup guides for Dart, including HttpServer, Serinus, and Routed.">
      <HomepageHeader />
      <main>
        <QuickStartSection />
        <PackagesTable />
        <HighlightsSection />
        <QuickLinks />
      </main>
    </Layout>
  );
}
