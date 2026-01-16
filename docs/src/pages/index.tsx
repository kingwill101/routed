import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';

import HomepageFeatures from '@site/src/components/HomepageFeatures';
import styles from './index.module.css';

const highlightCards = [
    {
        title: 'Turbo Ready',
        description:
            'routed_hotwire makes Turbo Streams and Stimulus controllers feel native to your Dart backend.',
    },
    {
        title: 'Server Testing',
        description:
            'server_testing reuses handlers across in-memory, real HTTP, and browser automation flows.',
    },
    {
        title: 'Routed Testing',
        description:
            'routed_testing layers engine-first helpers on server_testing transports.',
    },
    {
        title: 'Deterministic Generators',
        description:
            'Compose property_testing generators with shrinking, chaos categories, and state machines that plug straight into test.',
    },
];

const quickLinks = [
    {label: 'Engine & Middleware', to: '/docs/routed/fundamentals/'},
    {label: 'Storage & Caching', to: '/docs/routed/state/caching'},
    {label: 'Turbo Stream Responses', to: '/docs/routed_hotwire/'},
    {label: 'Test Transports', to: '/docs/server_testing/transports'},
    {label: 'Routed Testing', to: '/docs/routed_testing/'},
    {label: 'Property Testing Generators', to: '/docs/property_testing/'},
];

function HomepageHeader() {
  const {siteConfig} = useDocusaurusContext();
  return (
    <header className={clsx('hero hero--primary', styles.heroBanner)}>
      <div className="container">
          <Heading as="h1" className={styles.heroTitle}>
              Build faster with the Routed ecosystem
        </Heading>
          <p className={styles.heroSubtitle}>{siteConfig.tagline}</p>
        <div className={styles.buttons}>
            <Link className="button button--secondary button--lg" to="/docs/routed/">
                Explore Routed
            </Link>
            <Link className="button button--secondary button--lg" to="/docs/routed_hotwire/">
                Routed Hotwire Guides
            </Link>
            <Link className="button button--secondary button--lg" to="/docs/server_testing/">
                Server Testing Guides
            </Link>
            <Link className="button button--secondary button--lg" to="/docs/property_testing/">
                Property Testing Guides
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
                        <Heading as="h2">Install the essentials</Heading>
                        <p>
                            Bring in the runtime engine and add the testing toolkits to keep quality high from day one.
                            Each package
                            lives in the same repository and is versioned together.
                        </p>
                    </div>
                    <div className="col col--7">
                        <CodeBlock language="bash">
                            {`# Runtime framework
 dart pub add routed

# Hotwire helpers
 dart pub add routed_hotwire

# Server testing toolkit
 dart pub add --dev server_testing server_testing_shelf

# Routed testing helpers
 dart pub add --dev routed_testing

# Property-based testing utilities
 dart pub add --dev property_testing`}

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
                            <td><code>routed</code></td>
                            <td>HTTP engine, routing, controllers, middleware, templating</td>
                            <td><Link to="/docs/routed/">Routed docs</Link></td>
                        </tr>
                        <tr>
                            <td><code>routed_hotwire</code></td>
                            <td>Turbo Streams, frames, and Stimulus helpers</td>
                            <td><Link to="/docs/routed_hotwire/">Routed Hotwire docs</Link></td>
                        </tr>
                        <tr>
                            <td><code>server_testing</code></td>
                            <td>Fluent HTTP assertions, WebDriver integration, CLI helpers</td>
                            <td><Link to="/docs/server_testing/">Server Testing docs</Link></td>
                        </tr>
                        <tr>
                            <td><code>server_testing_shelf</code></td>
                            <td>Shelf adapter for <code>server_testing</code></td>
                            <td><Link to="/docs/server_testing_shelf/">Server Testing Shelf docs</Link></td>
                        </tr>
                        <tr>
                            <td><code>routed_testing</code></td>
                            <td>Routed-specific testing helpers</td>
                            <td><Link to="/docs/routed_testing/">Routed Testing docs</Link></td>
                        </tr>
                        <tr>
                            <td><code>property_testing</code></td>
                            <td>Generators, shrinking, chaos suites, stateful testing</td>
                            <td><Link to="/docs/property_testing/">Property Testing docs</Link></td>
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
                    Built to work together
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
                                    <Heading as="h4" style={{marginBottom: '0.5rem'}}>{item.label}</Heading>
                                    <span style={{
                                        fontSize: '0.85rem',
                                        color: 'var(--ifm-color-primary)'
                                    }}>Read more →</span>
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
        description="Routing, testing, and property-based tooling for Dart applications">
      <HomepageHeader />
      <main>
        <HomepageFeatures />
          <QuickStartSection/>
          <PackagesTable/>
          <HighlightsSection/>
          <QuickLinks/>
      </main>
    </Layout>
  );
}
