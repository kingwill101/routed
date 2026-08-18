import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';
import CodeBlock from '@theme/CodeBlock';

import styles from './index.module.css';

const packages = [
  {
    number: '01',
    name: 'routed',
    label: 'CORE FRAMEWORK',
    description: 'A composable HTTP engine for routes, middleware, context, views, and the things that make a service yours.',
    link: '/docs/routed/',
    color: 'lime',
  },
  {
    number: '02',
    name: 'routed_hotwire',
    label: 'INTERACTION',
    description: 'Turbo Streams, Frames, Stimulus helpers, and signed WebSocket broadcasts for server-rendered apps.',
    link: '/docs/routed_hotwire/',
    color: 'coral',
  },
  {
    number: '03',
    name: 'server_testing',
    label: 'CONFIDENCE',
    description: 'One testing vocabulary across in-memory handlers, real transports, and browser automation.',
    link: '/docs/server_testing/',
    color: 'blue',
  },
  {
    number: '04',
    name: 'routed_testing',
    label: 'FRAMEWORK TESTING',
    description: 'Engine-first helpers that keep your Routed tests focused on behavior instead of setup.',
    link: '/docs/routed_testing/',
    color: 'yellow',
  },
  {
    number: '05',
    name: 'property_testing',
    label: 'EDGE CASES',
    description: 'Generators, shrinking, chaos suites, and state machines for inputs your happy path forgot.',
    link: '/docs/property_testing/',
    color: 'pink',
  },
];

const pathways = [
  {label: 'Build an API', meta: 'routes · middleware · context', link: '/docs/routed/getting-started'},
  {label: 'Ship an interactive app', meta: 'Turbo · views', link: '/docs/routed_hotwire/'},
  {label: 'Test the whole path', meta: 'HTTP · browser · properties', link: '/docs/server_testing/intro'},
];

const quickLinks = [
  {label: 'Routing & middleware', note: 'The request path, made explicit.', link: '/docs/routed/fundamentals/routing'},
  {label: 'Portable host runtime', note: 'Dart servers, Node, edge, and more.', link: '/docs/routed/fundamentals/engine'},
  {label: 'Storage & sessions', note: 'Stateful features when you need them.', link: '/docs/routed/state/'},
  {label: 'Test transports', note: 'Use the same assertions everywhere.', link: '/docs/server_testing/transports'},
];

function RouteDiagram() {
  return (
    <div className={styles.routeDiagram} aria-label="A request moving through the Routed stack">
      <div className={styles.diagramTopline}>
        <span>REQUEST TRACE</span>
        <span className={styles.liveDot}>LIVE</span>
      </div>
      <div className={styles.tracePath}>
        <div className={styles.traceNode}>
          <span className={styles.traceIndex}>01</span>
          <strong>incoming</strong>
          <small>GET /orders/42</small>
        </div>
        <div className={styles.traceLine} />
        <div className={styles.traceNode}>
          <span className={styles.traceIndex}>02</span>
          <strong>middleware</strong>
          <small>auth · logging</small>
        </div>
        <div className={styles.traceLine} />
        <div className={`${styles.traceNode} ${styles.traceNodeAccent}`}>
          <span className={styles.traceIndex}>03</span>
          <strong>handler</strong>
          <small>OrderController.show</small>
        </div>
      </div>
      <div className={styles.traceFooter}>
        <span><i className={styles.okMark}>✓</i> response 200</span>
        <code>4.2ms</code>
      </div>
    </div>
  );
}

function HomepageHeader() {
  return (
    <header className={styles.hero}>
      <div className={styles.heroGrid} />
      <div className="container">
        <div className={styles.heroLayout}>
          <div className={styles.heroCopy}>
            <div className={styles.eyebrow}><span>ROUTED ECOSYSTEM</span><span className={styles.eyebrowRule} /></div>
            <Heading as="h1">The Dart toolkit for <em>shipping</em> backend systems.</Heading>
            <p className={styles.heroSubtitle}>
              Build the request path you mean. Routed gives you the engine; its friends give you the reach, feedback, and confidence to take it further.
            </p>
            <div className={styles.buttons}>
              <Link className={styles.primaryButton} to="/docs/routed/getting-started">
                Start with Routed <span>↗</span>
              </Link>
              <Link className={styles.textButton} to="/docs/routed/">
                Browse the docs <span>↓</span>
              </Link>
            </div>
            <div className={styles.heroMeta}>
              <span><b className={styles.metaDot} /> Dart-first</span>
              <span><b className={styles.metaDot} /> Modular by default</span>
              <span><b className={styles.metaDot} /> MIT licensed</span>
            </div>
          </div>
          <div className={styles.heroVisual}>
            <RouteDiagram />
            <div className={styles.heroStamp}>
              <span>ROUTE</span>
              <strong>YOUR<br />OWN<br /><i>WAY</i></strong>
            </div>
          </div>
        </div>
      </div>
      <div className={styles.heroRail}>
        <span>01 / ORIENT</span>
        <span>FRAMEWORK · INTERACTION · CONFIDENCE</span>
        <span>↓ SCROLL TO EXPLORE</span>
      </div>
    </header>
  );
}

function PathwaysSection() {
  return (
    <section className={styles.pathwaysSection}>
      <div className="container">
        <div className={styles.sectionIntro}>
          <div>
            <span className={styles.sectionKicker}>CHOOSE YOUR NEXT MOVE</span>
            <Heading as="h2">Start where the work is.</Heading>
          </div>
          <p>Routed is designed as a path, not a pile. Pick the job in front of you and find the smallest useful next step.</p>
        </div>
        <div className={styles.pathways}>
          {pathways.map((path, index) => (
            <Link className={styles.pathway} to={path.link} key={path.label}>
              <span className={styles.pathwayNumber}>0{index + 1}</span>
              <span className={styles.pathwayBody}><strong>{path.label}</strong><small>{path.meta}</small></span>
              <span className={styles.pathwayArrow}>↗</span>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}

function PackagesSection() {
  return (
    <section className={styles.packagesSection}>
      <div className="container">
        <div className={styles.sectionIntro}>
          <div>
            <span className={styles.sectionKicker}>THE TOOLCHAIN</span>
            <Heading as="h2">One ecosystem.<br /><em>Every sharp edge.</em></Heading>
          </div>
          <p>Use only what you need. Every package has its own boundary, its own docs, and a clear reason to exist.</p>
        </div>
        <div className={styles.packageGrid}>
          {packages.map((item) => (
            <Link className={`${styles.packageCard} ${styles[item.color]}`} to={item.link} key={item.name}>
              <div className={styles.packageCardTop}><span>{item.number}</span><span>{item.label}</span></div>
              <Heading as="h3"><code>{item.name}</code></Heading>
              <p>{item.description}</p>
              <span className={styles.cardLink}>Read the guide <span>↗</span></span>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}

function InstallSection() {
  return (
    <section className={styles.installSection}>
      <div className="container">
        <div className={styles.installLayout}>
          <div>
            <span className={styles.sectionKicker}>FIRST CONTACT</span>
            <Heading as="h2">A small start<br /><em>goes a long way.</em></Heading>
            <p>Install the core, add capability as your app earns it, and keep the same mental model from local server to production.</p>
            <Link className={styles.lightButton} to="/docs/routed/getting-started">Read the quick start <span>↗</span></Link>
          </div>
          <div className={styles.codeWindow}>
            <div className={styles.windowBar}><span className={styles.windowDots}><i /><i /><i /></span><span>terminal / routed_app</span><span>⌘ K</span></div>
            <CodeBlock language="bash" className={styles.codeBlock}>
              {'dart pub add routed\\n dart pub add --dev routed_cli\\n dart run routed_cli create --name my_app\\n cd my_app\\n dart run bin/server.dart'}
            </CodeBlock>
            <div className={styles.codeStatus}><span><b /> listening on http://localhost:8080</span><span>ready</span></div>
          </div>
        </div>
      </div>
    </section>
  );
}

function QuickLinksSection() {
  return (
    <section className={styles.quickLinksSection}>
      <div className="container">
        <div className={styles.quickLinksHeader}>
          <span className={styles.sectionKicker}>KEEP GOING</span>
          <Heading as="h2">The useful corners.</Heading>
        </div>
        <div className={styles.quickLinksGrid}>
          {quickLinks.map((item, index) => (
            <Link className={styles.quickLink} to={item.link} key={item.label}>
              <span>0{index + 1}</span>
              <strong>{item.label}</strong>
              <small>{item.note}</small>
              <b>↗</b>
            </Link>
          ))}
        </div>
      </div>
    </section>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout title="Routed ecosystem" description="A Dart toolkit for shipping backend systems.">
      <HomepageHeader />
      <main>
        <PathwaysSection />
        <PackagesSection />
        <InstallSection />
        <QuickLinksSection />
      </main>
    </Layout>
  );
}
