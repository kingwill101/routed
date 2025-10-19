# Template Components

This directory contains reusable template components that can be used across different templates using the
`{% render %}` liquid tag. This promotes maintainability, consistency, and DRY principles.

## Available Components

### 1. Post Card (`post_card.html`)

A versatile component for displaying blog posts in various layouts.

**Usage:**

```liquid
{% render 'components/post_card', post: post %}
{% render 'components/post_card', post: post, show_actions: true %}
{% render 'components/post_card', post: post, size: 'large' %}
```

**Parameters:**

- `post`: The post object to display (required)
- `show_actions`: Whether to show edit/delete buttons (default: false)
- `size`: 'small', 'medium', or 'large' (default: 'medium')

### 2. Post Meta (`post_meta.html`)

Displays author, date, and status information for posts.

**Usage:**

```liquid
{% render 'components/post_meta', post: post %}
{% render 'components/post_meta', post: post, size: 'large', show_updated: true %}
```

**Parameters:**

- `post`: The post object (required)
- `size`: 'small', 'medium', or 'large' (default: 'medium')
- `show_updated`: Whether to show updated date (default: false)

### 3. Statistics Cards (`stats_cards.html`)

Displays key metrics in a responsive grid layout.

**Usage:**

```liquid
{% assign stats = '' | split: '' %}
{% assign stats = stats | push: '{"value": 10, "label": "Total Posts", "color": "blue"}' %}
{% assign stats = stats | push: '{"value": 8, "label": "Published", "color": "green"}' %}
{% render 'components/stats_cards', stats: stats %}
```

**Parameters:**

- `stats`: Array of stat objects with value, label, and color properties (required)

### 4. Feature Cards (`feature_cards.html`)

Displays features with icons and descriptions in a grid layout.

**Usage:**

```liquid
{% render 'components/feature_cards', features: features %}
{% render 'components/feature_cards', features: features, columns: 2 %}
```

**Parameters:**

- `features`: Array of feature objects with title, description, and icon (required)
- `columns`: Number of columns (1-4, default: 3)

### 5. Pagination (`pagination.html`)

A comprehensive pagination component with ellipsis support.

**Usage:**

```liquid
{% render 'components/pagination', paginator: paginator %}
{% render 'components/pagination', paginator: paginator, search_query: search_query %}
```

**Parameters:**

- `paginator`: Pagination object with current_page, num_pages, has_next, has_previous (required)
- `search_query`: Optional search query to preserve in links

### 6. Search Form (`search_form.html`)

A reusable search form component with clear functionality.

**Usage:**

```liquid
{% render 'components/search_form', form: form, search_query: search_query %}
{% render 'components/search_form', form: form, search_query: search_query, show_clear: false %}
```

**Parameters:**

- `form`: The search form object (required)
- `search_query`: Current search query value (required)
- `show_clear`: Whether to show clear button (default: true)

### 7. Comment Form (`comment_form.html`)

A form component for submitting comments on blog posts.

**Usage:**

```liquid
{% render 'components/comment_form', form: form %}
{% render 'components/comment_form', form: form, success_message: success_message %}
```

**Parameters:**

- `form`: The comment form object (required)
- `success_message`: Optional success message to display

### 8. Newsletter Form (`newsletter_form.html`)

A newsletter signup form component.

**Usage:**

```liquid
{% render 'components/newsletter_form', form: form %}
{% render 'components/newsletter_form', form: form, success_message: success_message %}
```

**Parameters:**

- `form`: The newsletter form object (required)
- `success_message`: Optional success message to display

### 9. Navigation (`navigation.html`)

The main site navigation header.

**Usage:**

```liquid
{% render 'components/navigation' %}
{% render 'components/navigation', current_page: 'posts' %}
```

**Parameters:**

- `current_page`: Optional current page for highlighting active nav items

## Benefits of Component-Based Templates

1. **Reusability**: Components can be used across multiple templates
2. **Consistency**: Ensures uniform appearance and behavior
3. **Maintainability**: Changes to a component update all uses automatically
4. **DRY Principle**: Eliminates code duplication
5. **Modularity**: Templates become easier to understand and modify
6. **Testing**: Components can be tested in isolation

## Best Practices

1. **Document Parameters**: Always include usage examples and parameter descriptions
2. **Default Values**: Use `{% assign param = param | default: 'default_value' %}` for optional parameters
3. **Meaningful Names**: Use descriptive component and parameter names
4. **Size Variants**: Support different sizes (small, medium, large) when appropriate
5. **Error Handling**: Gracefully handle missing or invalid parameters
6. **Responsive Design**: Ensure components work well on all screen sizes

## Migration Benefits

The templates have been refactored to use these components, resulting in:

- **home.html**: Reduced from 120 lines to ~80 lines
- **list.html**: Reduced from 212 lines to ~90 lines
- **detail.html**: Reduced from 193 lines to ~120 lines
- **layout.html**: Cleaner navigation section

This makes the templates much easier to maintain and modify while ensuring consistency across the application. 