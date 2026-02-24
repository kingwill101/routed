export 'src/auth/manager/auth_manager.dart';
export 'src/auth/manager/auth_options.dart';
export 'src/auth/hooks.dart';
export 'src/auth/routes.dart';
export 'src/middleware/basic_auth.dart';
export 'src/middleware/csrf.dart';
export 'src/auth/haigate.dart'
    show
        GateCallback,
        GateEvaluation,
        GateEvaluationContext,
        GateObserver,
        GatePayloadProvider,
        GateDeniedHandler,
        GateRegistry,
        GateRegistrationException,
        GateViolation,
        Haigate;
export 'src/auth/jwt.dart' show JwtOnVerified, jwtAuthentication;
export 'src/auth/provider.dart' show AuthServiceProvider;
export 'src/auth/rbac.dart'
    show
        RbacAbility,
        RbacOptions,
        registerRbacAbilities,
        registerRbacAbilitiesSafely,
        registerRbacWithHaigate,
        rbacGate;
export 'src/auth/policies.dart'
    show
        Policy,
        PolicyAction,
        PolicyBinding,
        PolicyOptions,
        policyGate,
        registerPolicyBindings,
        registerPolicyBindingsSafely,
        registerPoliciesWithHaigate;

export 'src/auth/oauth.dart'
    show
        OAuthOnValidated,
        oauth2Introspection,
        oauthTokenAttribute,
        oauthClaimsAttribute,
        oauthScopeAttribute;
export 'src/auth/session_auth.dart'
    show
        RememberTokenStore,
        InMemoryRememberTokenStore,
        SessionAuthService,
        SessionAuth,
        GuardResult,
        AuthGuard,
        GuardRegistry,
        guardMiddleware,
        requireAuthenticated,
        requireRoles;
