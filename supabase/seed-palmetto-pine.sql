-- Palmetto & Pine Golf Co. beta drops on the Kiawah Island courses.
-- Run in the Supabase SQL editor after schema.sql. Safe to run again: it updates the drops'
-- wording and photos and extends their dates, but leaves how many are left alone.
--
-- Products, photos and links are from palmettoandpinegolf.com, used with the owner's OK for the beta.
--
-- Where the drops sit: the Kiawah courses ship in the app without hole positions (the phone gets
-- them from OpenStreetMap, or from tee and green spots golfers set), so these drops start at the
-- middle of the course and move to their hole's green the first time anyone starts a round there.
-- After that they follow the green every time the course map is saved.

-- The courses, so drops can point at them. The phone fills in the holes on its first round here.
insert into courses (id, name, data) values
  ('pack/ocean', 'The Ocean Course', '{"id": "pack/ocean", "name": "The Ocean Course", "holes": [], "source": "Gimme course pack"}'::jsonb),
  ('pack/turtle', 'Turtle Point', '{"id": "pack/turtle", "name": "Turtle Point", "holes": [], "source": "Gimme course pack"}'::jsonb),
  ('pack/cougar', 'Cougar Point', '{"id": "pack/cougar", "name": "Cougar Point", "holes": [], "source": "Gimme course pack"}'::jsonb),
  ('pack/osprey', 'Osprey Point', '{"id": "pack/osprey", "name": "Osprey Point", "holes": [], "source": "Gimme course pack"}'::jsonb),
  ('pack/cassique', 'Cassique', '{"id": "pack/cassique", "name": "Cassique", "holes": [], "source": "Gimme course pack"}'::jsonb),
  ('pack/river', 'The River Course', '{"id": "pack/river", "name": "The River Course", "holes": [], "source": "Gimme course pack"}'::jsonb)
on conflict (id) do nothing;

-- The brand. To let the owner see results in the brand dashboard, have them sign in to the app
-- once, then run (with their email):
--   insert into brand_members (brand_id, user_id)
--   select '5f880da5-2bde-5794-8944-5ad333eba5e9', id from auth.users where email = 'owner@example.com'
--   on conflict do nothing;
insert into brands (id, name) values ('5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine Golf Co.')
on conflict (id) do update set name = excluded.name;

-- Drops listed here move to their hole's green center whenever the course map is saved.
create table if not exists green_pinned_drops (
  drop_id uuid primary key references drops on delete cascade
);
alter table green_pinned_drops enable row level security;  -- no policies: only the function below reads it

create or replace function place_pinned_drops() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update drops d
     set lat = (h->'greenCenter'->>'latitude')::float8,
         lon = (h->'greenCenter'->>'longitude')::float8
    from jsonb_array_elements(coalesce(new.data->'holes', '[]'::jsonb)) h
   where d.course_id = new.id
     and (h->>'number')::int = d.hole
     and h->'greenCenter'->>'latitude' is not null
     -- Only a short move within the course, so an edited course map can't drag a prize off the island.
     and distance_m(d.lat, d.lon, (h->'greenCenter'->>'latitude')::float8, (h->'greenCenter'->>'longitude')::float8) < 3000
     and exists (select 1 from green_pinned_drops p where p.drop_id = d.id);
  return new;
end $$;

drop trigger if exists place_pinned_drops on courses;
create trigger place_pinned_drops after insert or update of data on courses
  for each row execute function place_pinned_drops();

-- The drops: 3 on the Ocean Course, 2 on each of the other courses.
insert into drops (id, brand_id, brand, prize, detail, course_id, hole, lat, lon, radius_m, challenge,
                   remaining, expires_at, headline, image_url, claim_url) values
  ('fb37425c-3a21-57ff-adfe-55fa1628222f', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Fore the Carolinas Rope Hat',
   'Fore the Carolinas Rope Hat from Palmetto & Pine, on the house for beta testers.',
   'pack/ocean', 17, 32.6124839857, -80.0226384401, 45, 'parOrBetter', 6, now() + interval '30 days',
   'Congrats! You just went “Fore the Carolinas”',
   'https://palmettoandpinegolf.com/cdn/shop/files/Product_Photos_20.png?v=1729101055&width=1080',
   'https://palmettoandpinegolf.com/products/fore-the-carolinas-rope-hat'),
  ('b699fa91-c6b9-581e-b6ea-692d3ff0bea9', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Carolina Comfort Hoodie',
   'The Carolina Comfort Hoodie from Palmetto & Pine, on the house for beta testers.',
   'pack/ocean', 18, 32.6124839857, -80.0226384401, 45, 'birdieOrBetter', 3, now() + interval '30 days',
   'Birdie on 18? That’s some real “Carolina Comfort”',
   'https://palmettoandpinegolf.com/cdn/shop/files/Product_Photos_6_b4d3d496-5d5d-4d8d-8403-4b9556bbd653.png?v=1760987557&width=1080',
   'https://palmettoandpinegolf.com/products/the-carolina-comfort-hoodie'),
  ('c0c8282a-4642-5fc6-ac21-42c0c1a502ce', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Laid Back Ball Marker',
   'The Laid Back Ball Marker from Palmetto & Pine, on the house for beta testers.',
   'pack/ocean', 5, 32.6124839857, -80.0226384401, 45, 'none', 10, now() + interval '30 days',
   'Mark it down. You’re officially “Laid Back”',
   'https://palmettoandpinegolf.com/cdn/shop/files/ProductPhotos_4b5f0c15-e346-47c8-93f8-a1d705ad1a44.png?v=1787250279&width=1080',
   'https://palmettoandpinegolf.com/products/the-laid-back-ball-marker-c3-custom-golf'),
  ('19ff514c-ed4f-5355-9843-e878cf20d8a6', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Palmetto & Pine Rope Hat',
   'Palmetto & Pine Rope Hat from Palmetto & Pine, on the house for beta testers.',
   'pack/turtle', 14, 32.6078025554, -80.0861477852, 45, 'parOrBetter', 5, now() + interval '30 days',
   'Congrats! You’ve got Palmetto & Pine written all over you',
   'https://palmettoandpinegolf.com/cdn/shop/files/Ad_Creative_5-20-26_18.png?v=1779714617&width=1080',
   'https://palmettoandpinegolf.com/products/palmetto-pine-rope-hat'),
  ('15a12a8e-67e8-5bf4-a538-9e26ed7158e1', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Support Your Local Muni Bumper Sticker',
   'Support Your Local Muni Bumper Sticker from Palmetto & Pine, on the house for beta testers.',
   'pack/turtle', 7, 32.6078025554, -80.0861477852, 45, 'none', 10, now() + interval '30 days',
   'Support your local muni. And your local Gimme.',
   'https://palmettoandpinegolf.com/cdn/shop/files/ProductPhotos_41.png?v=1733515396&width=1080',
   'https://palmettoandpinegolf.com/products/support-your-local-muni-bumper-sticker'),
  ('de2efc6a-3ee9-5ab6-947b-1112ed2bce30', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Palmetto & Pine Two Tone Hat',
   'Palmetto & Pine Two Tone Hat from Palmetto & Pine, on the house for beta testers.',
   'pack/cougar', 2, 32.5923015902, -80.1250330193, 45, 'parOrBetter', 5, now() + interval '30 days',
   'Two tones, one pure swing. The hat’s yours',
   'https://palmettoandpinegolf.com/cdn/shop/files/Ad_Creative_5-20-26_25.png?v=1779800199&width=1080',
   'https://palmettoandpinegolf.com/products/palmetto-pine-two-tone-hat'),
  ('9f8e8eeb-ab35-59ed-9935-dbda695cf6e8', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Dogwood & Jessamine Caddie Towel',
   'Dogwood & Jessamine Caddie Towel from Palmetto & Pine, on the house for beta testers.',
   'pack/cougar', 9, 32.5923015902, -80.1250330193, 45, 'none', 8, now() + interval '30 days',
   'Clean round, clean clubs. A Dogwood & Jessamine towel is yours',
   'https://palmettoandpinegolf.com/cdn/shop/files/Product_Photos_8_5e4693bb-6827-4f9f-bc5f-accbacd1d787.png?v=1778599117&width=1080',
   'https://palmettoandpinegolf.com/products/dogwood-jessamine-caddie-towel'),
  ('2f5074c4-dc82-5126-8bd7-9e539ddc4eab', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Fairway Stripes Headcovers',
   'Fairway Stripes Headcovers from Palmetto & Pine, on the house for beta testers.',
   'pack/osprey', 3, 32.6142100884, -80.053178072, 45, 'parOrBetter', 4, now() + interval '30 days',
   'Fairway found. Stripes earned.',
   'https://palmettoandpinegolf.com/cdn/shop/files/ProductPhotos_a7f07f45-344a-4b2f-8c2e-27bc43444e3b.png?v=1789932726&width=1080',
   'https://palmettoandpinegolf.com/products/fairway-stripes-headcovers-1'),
  ('24ffceb9-e46d-5564-b0c9-5f0334c7b921', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Fore the Carolinas Performance Hoodie',
   'Fore the Carolinas Performance Hoodie from Palmetto & Pine, on the house for beta testers.',
   'pack/osprey', 18, 32.6142100884, -80.053178072, 45, 'birdieOrBetter', 3, now() + interval '30 days',
   'Birdie on 18! That’s “Fore the Carolinas” performance',
   'https://palmettoandpinegolf.com/cdn/shop/files/Product_Photos_10_889c0986-724e-448e-bc3b-62d7dfacba91.png?v=1778600430&width=1080',
   'https://palmettoandpinegolf.com/products/fore-the-carolinas-performance-hoodie'),
  ('32e9e35c-2e10-55d4-8bed-72d3ceb3d334', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Fore the Carolinas T-Shirt',
   'Fore the Carolinas T-Shirt from Palmetto & Pine, on the house for beta testers.',
   'pack/cassique', 16, 32.5963148431, -80.1490670443, 45, 'parOrBetter', 6, now() + interval '30 days',
   'Congrats! You’re officially “Fore the Carolinas”',
   'https://palmettoandpinegolf.com/cdn/shop/files/Freedom_Release_3.png?v=1779714787&width=1080',
   'https://palmettoandpinegolf.com/products/the-fore-the-carolinas-shirt'),
  ('39bc8e23-4128-5b72-a32f-c3b296057dda', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Support Your Local Muni Bumper Sticker',
   'Support Your Local Muni Bumper Sticker from Palmetto & Pine, on the house for beta testers.',
   'pack/cassique', 1, 32.5963148431, -80.1490670443, 45, 'none', 10, now() + interval '30 days',
   'Support your local muni. And your local Gimme.',
   'https://palmettoandpinegolf.com/cdn/shop/files/ProductPhotos_41.png?v=1733515396&width=1080',
   'https://palmettoandpinegolf.com/products/support-your-local-muni-bumper-sticker'),
  ('a4afafa5-0af8-5c83-8f68-89a30db66286', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Palmetto & Pine Golf Company T-Shirt',
   'Palmetto & Pine Golf Company T-Shirt from Palmetto & Pine, on the house for beta testers.',
   'pack/river', 17, 32.6117610008, -80.0992369652, 45, 'parOrBetter', 6, now() + interval '30 days',
   'Palmetto & Pine says nice swing. Here’s the shirt.',
   'https://palmettoandpinegolf.com/cdn/shop/files/Product_Photos_24_e36d6787-d392-467d-b37f-80bee6a23302.png?v=1779804533&width=1080',
   'https://palmettoandpinegolf.com/products/palmetto-pine-golf-company-t-shirt'),
  ('03986600-cb01-5c54-91bc-396ad07a2574', '5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Laid Back Ball Marker',
   'The Laid Back Ball Marker from Palmetto & Pine, on the house for beta testers.',
   'pack/river', 3, 32.6117610008, -80.0992369652, 45, 'none', 8, now() + interval '30 days',
   'Mark it down. You’re officially “Laid Back”',
   'https://palmettoandpinegolf.com/cdn/shop/files/ProductPhotos_4b5f0c15-e346-47c8-93f8-a1d705ad1a44.png?v=1787250279&width=1080',
   'https://palmettoandpinegolf.com/products/the-laid-back-ball-marker-c3-custom-golf')
on conflict (id) do update set
  brand = excluded.brand, prize = excluded.prize, detail = excluded.detail, challenge = excluded.challenge,
  headline = excluded.headline, image_url = excluded.image_url, claim_url = excluded.claim_url,
  radius_m = excluded.radius_m, expires_at = greatest(drops.expires_at, excluded.expires_at);

insert into green_pinned_drops (drop_id) values ('fb37425c-3a21-57ff-adfe-55fa1628222f'), ('b699fa91-c6b9-581e-b6ea-692d3ff0bea9'), ('c0c8282a-4642-5fc6-ac21-42c0c1a502ce'), ('19ff514c-ed4f-5355-9843-e878cf20d8a6'), ('15a12a8e-67e8-5bf4-a538-9e26ed7158e1'), ('de2efc6a-3ee9-5ab6-947b-1112ed2bce30'), ('9f8e8eeb-ab35-59ed-9935-dbda695cf6e8'), ('2f5074c4-dc82-5126-8bd7-9e539ddc4eab'), ('24ffceb9-e46d-5564-b0c9-5f0334c7b921'), ('32e9e35c-2e10-55d4-8bed-72d3ceb3d334'), ('39bc8e23-4128-5b72-a32f-c3b296057dda'), ('a4afafa5-0af8-5c83-8f68-89a30db66286'), ('03986600-cb01-5c54-91bc-396ad07a2574')
on conflict do nothing;

-- Courses someone already played: move the drops onto their greens now.
update courses set data = data where id like 'pack/%';

-- Restock a drop for another weekend:
--   update drops set remaining = 10, expires_at = now() + interval '30 days'
--   where brand_id = '5f880da5-2bde-5794-8944-5ad333eba5e9' and course_id = 'pack/ocean' and hole = 17;

-- ─── Test drop anywhere ───────────────────────────────────────────────────────────────
-- To try a drop without driving to Kiawah (a backyard, a practice green, your home course):
-- 1. In the app, start a round on the course you'll test on. Claims only work during an active
--    round on the drop's course, so the drop must use that round's course id.
-- 2. Find that course id:  select course_id from rounds order by started_at desc limit 1;
-- 3. Stand where you want the drop, read your latitude and longitude (Apple Maps: drop a pin),
--    and run this with those numbers. Don't add it to green_pinned_drops, or it will jump to the green.
--
-- insert into drops (brand_id, brand, prize, detail, course_id, hole, lat, lon, radius_m, challenge,
--                    remaining, expires_at, headline, image_url, claim_url)
-- values ('5f880da5-2bde-5794-8944-5ad333eba5e9', 'Palmetto & Pine', 'Free Fore the Carolinas Rope Hat',
--         'Fore the Carolinas Rope Hat from Palmetto & Pine, on the house for beta testers.',
--         'PASTE COURSE ID', 1, 32.6125, -80.0226, 60, 'none', 5, now() + interval '2 days',
--         'Congrats! You just went “Fore the Carolinas”',
--         'https://palmettoandpinegolf.com/cdn/shop/files/Product_Photos_20.png?v=1729101055&width=1080',
--         'https://palmettoandpinegolf.com/products/fore-the-carolinas-rope-hat');
