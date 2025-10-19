import type {ReactNode} from 'react';
import clsx from 'clsx';
import Link from '@docusaurus/Link';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  Svg: React.ComponentType<React.ComponentProps<'svg'>>;
  description: ReactNode;
    link: string;
    linkLabel: string;
};

const FeatureList: FeatureItem[] = [
  {
      title: 'Routed Core',
    Svg: require('@site/static/img/undraw_docusaurus_mountain.svg').default,
    description: (
      <>
          Compose routers, controllers, middleware, and views with a pragmatic HTTP engine built for production Dart
          services.
      </>
    ),
      link: '/docs/routed/',
      linkLabel: 'Start building',
  },
  {
      title: 'Server Testing Toolkit',
    Svg: require('@site/static/img/undraw_docusaurus_tree.svg').default,
    description: (
      <>
          Reuse the same handler for fast in-memory tests, real HTTP transports, and full browser automation with CLI
          support.
      </>
    ),
      link: '/docs/server-testing/',
      linkLabel: 'See testing guides',
  },
  {
      title: 'Property-Based Confidence',
    Svg: require('@site/static/img/undraw_docusaurus_react.svg').default,
    description: (
      <>
          Generate adversarial inputs, shrink failures, and model stateful systems with the property_testing toolkit.
      </>
    ),
      link: '/docs/property-testing/',
      linkLabel: 'Explore generators',
  },
];

function Feature({title, Svg, description, link, linkLabel}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Svg className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
          <Link className="button button--link button--sm" to={link}>
              {linkLabel} →
          </Link>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
