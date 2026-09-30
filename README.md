# to you — Phase 6 Real Backend + Personal Style

This build keeps the existing Phase 5 visual design and changes only the requested details:

- real-account Supabase foundation for profiles, habits, tasks, goals, completions and journey events
- private-by-default RLS policies
- real connection-code flow for Me ↔ Her
- independent account preferences
- Classic style preserved for the current design
- optional Soft Rose **girl style** for her own account; it does not change your account
- Journey events can now attach a photo
- Journey photos use Supabase Storage when configured, with local fallback in the prototype
- streak/check completion animation is upgraded without changing the layout
- personal goals have removable records; suggested goals are only suggestions, not locked items

## Supabase setup

1. Create/open your Supabase project.
2. **Do not rerun `schema.sql` on the live project.** The live database has newer migrations/schema than this historical bootstrap file; the current project is already configured.
3. Enable Google provider in Supabase Authentication if you want Google sign-in.
4. Set the Google OAuth redirect URL to your deployed app URL.
5. Put only the public project URL and anon/publishable key in `config.js`.
6. Never put a `service_role` key in this app.

## Important

The SQL is designed so every real account is independent. "Her" is not a permanent demo account. A connected partner only becomes visible after both people intentionally connect.

This build does not publish or deploy anything.
