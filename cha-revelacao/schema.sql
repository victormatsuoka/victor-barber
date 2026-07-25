-- =====================================================================
-- Chá de bebê + Revelação — Miguel ou Zoe? · Esquema Supabase
-- Rode este arquivo inteiro no SQL Editor do seu projeto Supabase.
-- Depois: Auth > Users > crie os usuários de Victor e Paula e ajuste
-- os e-mails em admin_users logo abaixo.
-- =====================================================================
create extension if not exists pgcrypto;

-- ------------------------- administradores ---------------------------
create table if not exists admin_users (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  display_name text
);
-- TROQUE pelos e-mails reais que Victor e Paula usarão no login:
insert into admin_users (email, display_name) values
  ('victor@EXEMPLO.com', 'Victor'),
  ('paula@EXEMPLO.com', 'Paula')
on conflict (email) do nothing;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from admin_users a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- ---------------------------- convidados -----------------------------
create table if not exists guests (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null,
  companions int not null default 0,
  attendance_status text not null default 'confirmed'
    check (attendance_status in ('confirmed','cancelled','pending','no_show')),
  gender_vote text check (gender_vote in ('miguel','zoe')),
  confirm_code text not null default lpad((floor(random()*10000))::int::text, 4, '0'),
  notes text,
  arrived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists guests_phone_idx on guests (phone);

-- ----------------------------- presentes -----------------------------
create table if not exists gifts (
  id text primary key,
  name text not null,
  category text not null,
  description text,
  image_url text,
  icon text,
  price_min_yen int,
  price_max_yen int,
  store_name text,
  product_reference_url text,
  color text,
  display_order int not null default 0,
  featured boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists gift_reservations (
  id uuid primary key default gen_random_uuid(),
  gift_id text not null references gifts(id) on delete cascade,
  guest_id uuid references guests(id) on delete set null,
  guest_name text not null,
  guest_phone text not null,
  message text,
  status text not null default 'reserved'
    check (status in ('reserved','received','cancelled')),
  reserved_at timestamptz not null default now(),
  received_at timestamptz,
  cancelled_at timestamptz
);
-- SERVIDOR impede duas reservas ativas do mesmo presente:
create unique index if not exists one_active_reservation_per_gift
  on gift_reservations (gift_id) where (status in ('reserved','received'));

-- ------------------------------ fraldas -------------------------------
create table if not exists diaper_choices (
  id uuid primary key default gen_random_uuid(),
  guest_id uuid references guests(id) on delete set null,
  guest_name text,
  guest_phone text,
  size text not null check (size in ('新生児','S','M','L','Big')),
  brand text not null default 'Sem preferência',
  package_quantity int not null default 1 check (package_quantity between 1 and 20),
  status text not null default 'promised'
    check (status in ('promised','received','cancelled')),
  received_quantity int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- --------------------- palpite Miguel ou Zoe (torcida) ------------------
-- Ledger anônimo: 1 voto por dispositivo (token aleatório salvo no navegador
-- do convidado), sem nome nem telefone. Não é lido publicamente — só serve
-- para alimentar o agregado abaixo.
create table if not exists gender_votes (
  id uuid primary key default gen_random_uuid(),
  voter_token text not null unique,
  vote text not null check (vote in ('miguel','zoe')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Agregado público: só os totais, nunca votos individuais.
create table if not exists vote_tally (
  id smallint primary key default 1 check (id = 1),
  miguel_count int not null default 0,
  zoe_count int not null default 0,
  updated_at timestamptz not null default now()
);
insert into vote_tally (id) values (1) on conflict (id) do nothing;

create or replace function recompute_vote_tally() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update vote_tally set
    miguel_count = (select count(*) from gender_votes where vote = 'miguel'),
    zoe_count = (select count(*) from gender_votes where vote = 'zoe'),
    updated_at = now()
  where id = 1;
  return null;
end $$;

drop trigger if exists trg_vote_tally on gender_votes;
create trigger trg_vote_tally
  after insert or update of vote or delete on gender_votes
  for each row execute function recompute_vote_tally();

-- --------------------- mensagens para o bebê --------------------------
create table if not exists baby_messages (
  id uuid primary key default gen_random_uuid(),
  guest_id uuid references guests(id) on delete set null,
  guest_name text,
  guest_phone text,
  recipient_type text not null default 'baby'
    check (recipient_type in ('miguel','zoe','baby')),
  message text not null check (char_length(message) <= 600),
  capsule boolean not null default false,
  favorite boolean not null default false,
  status text not null default 'new' check (status in ('new','read','hidden')),
  read_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists admin_notes (
  id uuid primary key default gen_random_uuid(),
  guest_id uuid references guests(id) on delete cascade,
  note text not null,
  created_at timestamptz not null default now()
);

create table if not exists settings (
  key text primary key,
  value text
);
insert into settings (key, value) values ('diaper_priority', ''), ('invite_url', ''), ('vote_reveal_mode', 'after_vote')
on conflict (key) do nothing;

-- ------------------------------- RLS ----------------------------------
alter table admin_users enable row level security;
alter table guests enable row level security;
alter table gifts enable row level security;
alter table gift_reservations enable row level security;
alter table diaper_choices enable row level security;
alter table baby_messages enable row level security;
alter table admin_notes enable row level security;
alter table settings enable row level security;
alter table gender_votes enable row level security;
alter table vote_tally enable row level security;

-- administradores: acesso total
create policy admin_all_guests on guests for all using (is_admin()) with check (is_admin());
create policy admin_all_gifts on gifts for all using (is_admin()) with check (is_admin());
create policy admin_all_res on gift_reservations for all using (is_admin()) with check (is_admin());
create policy admin_all_diapers on diaper_choices for all using (is_admin()) with check (is_admin());
create policy admin_all_msgs on baby_messages for all using (is_admin()) with check (is_admin());
create policy admin_all_notes on admin_notes for all using (is_admin()) with check (is_admin());
create policy admin_all_settings on settings for all using (is_admin()) with check (is_admin());
create policy admin_all_votes on gender_votes for all using (is_admin()) with check (is_admin());
create policy admin_all_tally on vote_tally for all using (is_admin()) with check (is_admin());
create policy admin_read_admins on admin_users for select using (is_admin());

-- público (anon): só o necessário — catálogo ativo e prioridade de fraldas
create policy public_read_gifts on gifts for select using (active = true);
create policy public_read_priority on settings for select using (key in ('diaper_priority','vote_reveal_mode'));
-- torcida pública: só o agregado, nunca a tabela gender_votes (sem policy de select para anon nela).
create policy public_read_tally on vote_tally for select using (true);
-- nenhuma leitura pública de guests / reservas / fraldas / mensagens.

-- status público dos presentes SEM dados pessoais:
create or replace view public_gift_status as
  select gift_id, status from gift_reservations
  where status in ('reserved','received');
grant select on public_gift_status to anon, authenticated;

-- --------------------- funções públicas (RPC) -------------------------
-- Confirmação completa do convidado (presença + fralda + presente + mensagem)
create or replace function public_confirm(
  p_name text, p_phone text, p_companions int default 0,
  p_vote text default null,
  p_diaper_size text default null, p_diaper_brand text default 'Sem preferência',
  p_diaper_qty int default 1,
  p_gift_id text default null, p_gift_message text default null,
  p_baby_recipient text default null, p_baby_message text default null,
  p_baby_capsule boolean default false
) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_guest guests%rowtype;
  v_code text;
begin
  if coalesce(trim(p_name),'') = '' or coalesce(trim(p_phone),'') = '' then
    return json_build_object('ok', false, 'error', 'nome_telefone_obrigatorios');
  end if;

  select * into v_guest from guests where phone = trim(p_phone) limit 1;
  if not found then
    insert into guests (full_name, phone, companions, gender_vote)
    values (trim(p_name), trim(p_phone), greatest(p_companions,0), p_vote)
    returning * into v_guest;
  else
    update guests set
      full_name = trim(p_name),
      companions = greatest(p_companions, 0),
      gender_vote = coalesce(p_vote, gender_vote),
      attendance_status = 'confirmed',
      updated_at = now()
    where id = v_guest.id returning * into v_guest;
  end if;
  v_code := v_guest.confirm_code;

  if p_diaper_size is not null then
    insert into diaper_choices (guest_id, guest_name, guest_phone, size, brand, package_quantity)
    values (v_guest.id, v_guest.full_name, v_guest.phone, p_diaper_size,
            coalesce(nullif(trim(p_diaper_brand),''),'Sem preferência'),
            greatest(coalesce(p_diaper_qty,1),1));
  end if;

  if p_gift_id is not null then
    begin
      insert into gift_reservations (gift_id, guest_id, guest_name, guest_phone, message)
      values (p_gift_id, v_guest.id, v_guest.full_name, v_guest.phone, p_gift_message);
    exception when unique_violation then
      return json_build_object('ok', false, 'error', 'presente_ja_escolhido', 'code', v_code);
    end;
  end if;

  if coalesce(trim(p_baby_message),'') <> '' then
    insert into baby_messages (guest_id, guest_name, guest_phone, recipient_type, message, capsule)
    values (v_guest.id, v_guest.full_name, v_guest.phone,
            coalesce(nullif(p_baby_recipient,''),'baby'), left(trim(p_baby_message), 600),
            coalesce(p_baby_capsule, false));
  end if;

  return json_build_object('ok', true, 'code', v_code, 'guest_id', v_guest.id);
end $$;
grant execute on function public_confirm to anon, authenticated;

-- Palpite Miguel ou Zoe: anônimo, 1 voto por dispositivo, sem exigir cadastro.
create or replace function public_cast_vote(p_token text, p_vote text) returns json
language plpgsql security definer set search_path = public as $$
begin
  if p_vote not in ('miguel','zoe') or coalesce(trim(p_token),'') = '' then
    return json_build_object('ok', false, 'error', 'voto_invalido');
  end if;
  insert into gender_votes (voter_token, vote)
  values (trim(p_token), p_vote)
  on conflict (voter_token) do update set vote = excluded.vote, updated_at = now();
  return json_build_object('ok', true);
end $$;
grant execute on function public_cast_vote to anon, authenticated;

-- Minhas escolhas: consulta por telefone + código
create or replace function my_choices(p_phone text, p_code text) returns json
language plpgsql stable security definer set search_path = public as $$
declare v_guest guests%rowtype;
begin
  select * into v_guest from guests
  where phone = trim(p_phone) and confirm_code = trim(p_code) limit 1;
  if not found then return json_build_object('ok', false, 'error', 'nao_encontrado'); end if;
  return json_build_object('ok', true,
    'guest', json_build_object('id', v_guest.id, 'name', v_guest.full_name,
      'companions', v_guest.companions, 'status', v_guest.attendance_status,
      'vote', v_guest.gender_vote),
    'diapers', (select coalesce(json_agg(json_build_object('id', d.id, 'size', d.size,
      'brand', d.brand, 'qty', d.package_quantity, 'status', d.status)), '[]'::json)
      from diaper_choices d where d.guest_id = v_guest.id and d.status <> 'cancelled'),
    'gifts', (select coalesce(json_agg(json_build_object('id', r.id, 'gift_id', r.gift_id,
      'name', g.name, 'status', r.status)), '[]'::json)
      from gift_reservations r join gifts g on g.id = r.gift_id
      where r.guest_id = v_guest.id and r.status <> 'cancelled'),
    'messages', (select coalesce(json_agg(json_build_object('id', m.id,
      'recipient', m.recipient_type, 'message', m.message)), '[]'::json)
      from baby_messages m where m.guest_id = v_guest.id and m.status <> 'hidden'));
end $$;
grant execute on function my_choices to anon, authenticated;

-- Alterações do próprio convidado (sempre validadas por telefone + código)
create or replace function my_update_diaper(p_phone text, p_code text, p_id uuid,
  p_size text, p_brand text, p_qty int) returns json
language plpgsql security definer set search_path = public as $$
declare v_guest guests%rowtype;
begin
  select * into v_guest from guests where phone = trim(p_phone) and confirm_code = trim(p_code);
  if not found then return json_build_object('ok', false); end if;
  update diaper_choices set size = p_size, brand = p_brand,
    package_quantity = greatest(p_qty,1), updated_at = now()
  where id = p_id and guest_id = v_guest.id;
  return json_build_object('ok', true);
end $$;
grant execute on function my_update_diaper to anon, authenticated;

create or replace function my_cancel_gift(p_phone text, p_code text, p_id uuid) returns json
language plpgsql security definer set search_path = public as $$
declare v_guest guests%rowtype;
begin
  select * into v_guest from guests where phone = trim(p_phone) and confirm_code = trim(p_code);
  if not found then return json_build_object('ok', false); end if;
  update gift_reservations set status = 'cancelled', cancelled_at = now()
  where id = p_id and guest_id = v_guest.id and status = 'reserved';
  return json_build_object('ok', true);
end $$;
grant execute on function my_cancel_gift to anon, authenticated;

create or replace function my_update_message(p_phone text, p_code text, p_id uuid,
  p_recipient text, p_message text) returns json
language plpgsql security definer set search_path = public as $$
declare v_guest guests%rowtype;
begin
  select * into v_guest from guests where phone = trim(p_phone) and confirm_code = trim(p_code);
  if not found then return json_build_object('ok', false); end if;
  update baby_messages set recipient_type = coalesce(nullif(p_recipient,''),'baby'),
    message = left(trim(p_message), 600), updated_at = now()
  where id = p_id and guest_id = v_guest.id;
  return json_build_object('ok', true);
end $$;
grant execute on function my_update_message to anon, authenticated;

-- ------------------- storage para imagens dos presentes ----------------
insert into storage.buckets (id, name, public) values ('gift-images','gift-images', true)
on conflict (id) do nothing;
create policy gift_images_public_read on storage.objects
  for select using (bucket_id = 'gift-images');
create policy gift_images_admin_write on storage.objects
  for all using (bucket_id = 'gift-images' and is_admin())
  with check (bucket_id = 'gift-images' and is_admin());

-- --------------------------- tempo real --------------------------------
alter publication supabase_realtime add table guests, gift_reservations,
  diaper_choices, baby_messages, gifts, vote_tally;

-- ------------------------ seed: ~100 presentes -------------------------
insert into gifts (id, name, category, description, price_min_yen, price_max_yen, icon, display_order) values
  ('fr-lencos8','Lenços umedecidos (leve 8)','Fraldas','Caixa com vários pacotes — Merries ou Moony.',600,1000,'ic-lencos',10),
  ('fr-refil','Refil de lenços umedecidos','Fraldas','Pacotes de reposição, sempre bem-vindos.',300,600,'ic-lencos',20),
  ('fr-bos','Saquinhos para fraldas usadas','Fraldas','BOS anti-odor, rolinho prático.',300,500,'ic-lixeira',30),
  ('fr-lixeira','Lixeira anti-odor','Fraldas','Combi Poitech ou similar.',2500,3500,'ic-lixeira',40),
  ('fr-cartucho','Refil da lixeira','Fraldas','Cartucho de reposição.',800,1200,'ic-lixeira',50),
  ('fr-trocador','Trocador portátil','Fraldas','Dobrável, para os passeios.',1500,2500,'ic-trocador',60),
  ('fr-tapete','Tapete de troca impermeável','Fraldas','Para usar em casa.',1000,1800,'ic-trocador',70),
  ('fr-organizador','Organizador de fraldas','Fraldas','Cesto com divisórias para o quarto.',1500,2500,'ic-cesto',80),
  ('fr-pomada','Pomada de assadura','Fraldas','Pigeon ou Polibaby, tubo grande.',800,1200,'ic-tubo',90),
  ('fr-drywipes','Toalhinhas secas de algodão','Fraldas','Dry wipes multiuso, suaves.',400,700,'ic-algodao',100),
  ('fr-porta','Porta-lenços com tampa','Fraldas','Mantém os lenços sempre úmidos.',600,1000,'ic-lencos',110),
  ('fr-natacao','Fralda de natação','Fraldas','Moony água, estampa neutra.',800,1200,'ic-fralda',120),
  ('fr-kitviagem','Kit de troca para viagem','Fraldas','Nécessaire compacta para a bolsa.',1500,2500,'ic-bolsa',130),
  ('fr-pano','Fraldas de pano (kit)','Fraldas','Algodão em tons neutros.',2000,3000,'ic-toalha',140),
  ('hi-sabonete','Sabonete líquido de bebê','Higiene','Arau Baby ou Pigeon, espuma suave.',400,700,'ic-frasco',150),
  ('hi-shampoo','Shampoo suave','Higiene','Fácil de enxaguar, sem lágrimas.',400,800,'ic-frasco',160),
  ('hi-locao','Loção hidratante','Higiene','Momo no Ha, folha de pêssego.',700,1100,'ic-frasco',170),
  ('hi-oleo','Óleo de massagem baby','Higiene','Para a pele e o carinho.',600,1000,'ic-colonia',180),
  ('hi-algodao','Algodão de maternidade','Higiene','Quadradinhos macios.',300,500,'ic-algodao',190),
  ('hi-hastes','Hastes flexíveis de bebê','Higiene','Com trava de segurança.',200,400,'ic-algodao',200),
  ('hi-gaze','Gaze esterilizada','Higiene','Multiuso, indispensável.',300,600,'ic-toalha',210),
  ('hi-unha','Cortador de unhas baby','Higiene','Pigeon, tesourinha com ponta redonda.',800,1300,'ic-tesoura',220),
  ('hi-escova','Kit escova e pente macios','Higiene','Cerdas delicadas.',800,1400,'ic-escova',230),
  ('hi-termometro','Termômetro digital','Higiene','Medição rápida e silenciosa.',1200,2500,'ic-termometro',240),
  ('hi-aspirador','Aspirador nasal','Higiene','Pigeon ou ChuChu, manual.',1500,2500,'ic-aspirador',250),
  ('hi-sabao','Sabão para roupas de bebê','Higiene','Arau ou Sarasa, sem perfume forte.',400,700,'ic-frasco',260),
  ('hi-solar','Protetor solar baby','Higiene','Suave, fácil de remover.',800,1500,'ic-sol',270),
  ('hi-creme','Creme multiuso','Higiene','Proteção diária para as bochechas.',500,900,'ic-tubo',280),
  ('hi-kit','Kit higiene completo','Higiene','Escova, pente e tesourinha.',1000,1800,'ic-tesoura',290),
  ('ba-banheira','Banheira dobrável','Banho','Richell, fácil de guardar.',2500,4000,'ic-banheira',300),
  ('ba-apoio','Apoio de banho','Banho','Cadeirinha reclinada para a banheira.',2000,3500,'ic-banheira',310),
  ('ba-termometro','Termômetro de banho','Banho','Para a água na temperatura certa.',800,1500,'ic-termometro',320),
  ('ba-toalha','Toalha com capuz','Banho','Algodão, tom cru.',1500,3000,'ic-toalha',330),
  ('ba-toalhinhas','Toalhinhas de rosto (kit)','Banho','Gaze macia, várias unidades.',500,1000,'ic-toalha',340),
  ('ba-esponja','Esponja natural macia','Banho','Delicada com a pele.',300,600,'ic-algodao',350),
  ('ba-copinho','Copinho de enxágue','Banho','Não deixa entrar água nos olhos.',400,800,'ic-copo',360),
  ('ba-roupao','Roupão saída de banho','Banho','Unissex, bege.',2000,3500,'ic-casaco',370),
  ('ba-tapete','Tapete antiderrapante','Banho','Segurança na hora do banho.',800,1500,'ic-tapete',380),
  ('ba-regador','Regador de banho','Banho','Madeira ou tons neutros, diverte e enxagua.',500,1000,'ic-copo',390),
  ('ro-bodycurto','Kit bodies manga curta','Roupinhas','Uniqlo ou MUJI, tom cru.',1000,2000,'ic-body',400),
  ('ro-bodylongo','Kit bodies manga longa','Roupinhas','Algodão macio, cores neutras.',1000,2000,'ic-body',410),
  ('ro-macacao','Macacão de algodão','Roupinhas','Tom sálvia ou bege.',1500,2500,'ic-body',420),
  ('ro-pijama','Pijama romper','Roupinhas','Algodão orgânico.',1500,2800,'ic-body',430),
  ('ro-conjunto','Conjuntinho 2 peças','Roupinhas','Neutro e fofo.',1500,2500,'ic-casaco',440),
  ('ro-mijao','Calça mijão (kit 2)','Roupinhas','Cintura suave, sem apertar.',1000,1800,'ic-calca',450),
  ('ro-meias','Meias (kit 3 pares)','Roupinhas','Tamanho recém-nascido.',500,900,'ic-meia',460),
  ('ro-luvinhas','Luvinhas anti-arranhão','Roupinhas','Algodão fininho.',300,600,'ic-meia',470),
  ('ro-touca','Touca de algodão','Roupinhas','Para os primeiros passeios.',500,900,'ic-touca',480),
  ('ro-chapeu','Chapéu de sol','Roupinhas','Com proteção de nuca.',800,1500,'ic-chapeu',490),
  ('ro-babadores','Babadores (kit 3)','Roupinhas','Tons neutros.',800,1500,'ic-babador',500),
  ('ro-fraldaboca','Fraldas de boca (kit)','Roupinhas','Gaze dupla, macias.',600,1000,'ic-toalha',510),
  ('ro-casaquinho','Casaquinho de linha','Roupinhas','Creme, feito para durar.',1500,3000,'ic-casaco',520),
  ('ro-manta','Manta de algodão','Roupinhas','Leve e quentinha.',1500,3000,'ic-toalha',530),
  ('ro-sleeper','Saco de dormir (sleeper)','Roupinhas','Sono seguro no berço.',2000,3500,'ic-lua',540),
  ('al-mamadeira','Mamadeira Pigeon','Alimentação','Bico natural, vidro ou plástico.',1200,2000,'ic-mamadeira',550),
  ('al-bicos','Bicos de reposição','Alimentação','Pigeon, fase recém-nascido.',600,1000,'ic-chupeta',560),
  ('al-escova','Escova de mamadeira','Alimentação','Com esponja para o bico.',300,600,'ic-escova',570),
  ('al-detergente','Detergente para mamadeira','Alimentação','Combi ou Pigeon, uso diário.',300,600,'ic-frasco',580),
  ('al-esterilizador','Saco esterilizador','Alimentação','Esteriliza no micro-ondas.',800,1400,'ic-pote',590),
  ('al-babador','Babador de silicone','Alimentação','Com cata-migalhas.',800,1500,'ic-babador',600),
  ('al-colheres','Kit colheres de silicone','Alimentação','Richell, pontas macias.',500,1000,'ic-colher',610),
  ('al-copo','Copo de treinamento','Alimentação','Combi step-up, com alças.',800,1500,'ic-copo',620),
  ('al-potinhos','Potinhos para papinha','Alimentação','Empilháveis, com tampa.',800,1300,'ic-pote',630),
  ('al-garrafa','Garrafa térmica','Alimentação','Água quente para o leite nos passeios.',2000,3500,'ic-garrafa',640),
  ('qu-lencol','Lençol de berço','Quarto','Algodão cru.',1000,2000,'ic-toalha',650),
  ('qu-protetor','Protetor de colchão','Quarto','Impermeável e silencioso.',1000,1800,'ic-toalha',660),
  ('qu-cobertor','Cobertor de berço','Quarto','Tom sálvia.',1500,3000,'ic-lua',670),
  ('qu-luminaria','Luminária noturna','Quarto','Luz quente regulável.',1500,2800,'ic-luminaria',680),
  ('qu-mobile','Móbile de berço','Quarto','Tons terrosos, gira devagarinho.',1500,3000,'ic-mobile',690),
  ('qu-cesto','Cesto organizador','Quarto','Palha ou algodão.',800,1500,'ic-cesto',700),
  ('qu-cabides','Cabides de bebê (kit 10)','Quarto','Tamanho mini.',300,600,'ic-cabide',710),
  ('qu-almofada','Almofada de amamentação','Quarto','Conforto para os dois.',1500,3000,'ic-lua',720),
  ('qu-travesseiro','Travesseiro donut','Quarto','Acolhe a cabecinha.',1000,2000,'ic-lua',730),
  ('qu-umidificador','Umidificador compacto','Quarto','Para o inverno seco do Japão.',2000,3500,'ic-vento',740),
  ('pa-bolsa','Bolsa de passeio','Passeio','Mother bag compacta, tom neutro.',2000,3500,'ic-bolsa',750),
  ('pa-manta','Manta para carrinho','Passeio','Não voa com o vento.',1500,2500,'ic-toalha',760),
  ('pa-sol','Protetor de sol para carrinho','Passeio','Tela leve, dobrável.',1000,2000,'ic-sol',770),
  ('pa-mosquiteiro','Mosquiteiro de carrinho','Passeio','Verão tranquilo.',800,1500,'ic-carrinho',780),
  ('pa-chuva','Capa de chuva de carrinho','Passeio','Época das chuvas sem susto.',1000,1800,'ic-guarda',790),
  ('pa-ganchos','Ganchos para carrinho','Passeio','Pendura as sacolinhas.',500,900,'ic-carrinho',800),
  ('pa-organizador','Organizador de carrinho','Passeio','Porta-copo e celular.',1000,2000,'ic-carrinho',810),
  ('pa-ventilador','Ventilador portátil','Passeio','Para o verão japonês.',1500,2500,'ic-vento',820),
  ('pa-espelho','Espelho para o carro','Passeio','Bebê sempre à vista.',1000,1800,'ic-espelho',830),
  ('pa-lencinhos','Lencinhos de bolso (kit)','Passeio','Sempre na bolsa.',300,500,'ic-lencos',840),
  ('br-chocalho','Chocalho de madeira','Brinquedos','Toque suave, som delicado.',500,1000,'ic-chocalho',850),
  ('br-mordedor','Mordedor de banana','Brinquedos','Clássico japonês para a dentição.',500,800,'ic-chocalho',860),
  ('br-naninha','Naninha','Brinquedos','Tecido macio, tom cru.',1000,2000,'ic-urso',870),
  ('br-urso','Ursinho de pelúcia','Brinquedos','O primeiro amigo.',1000,2500,'ic-urso',880),
  ('br-livropano','Livrinho de pano','Brinquedos','Texturas para descobrir.',800,1500,'ic-livro',890),
  ('br-livrobanho','Livrinho de banho','Brinquedos','Histórias na banheira.',500,1000,'ic-livro',900),
  ('br-bola','Bola de tecido','Brinquedos','Leve e fácil de segurar.',800,1500,'ic-bola',910),
  ('br-cubos','Cubos macios','Brinquedos','Empilhar e derrubar.',1000,2000,'ic-cubos',920),
  ('br-aneis','Anéis de empilhar','Brinquedos','Madeira ou tecido.',1000,2000,'ic-aneis',930),
  ('br-pulso','Chocalho de pulso (par)','Brinquedos','Chacoalha junto com o bebê.',500,900,'ic-chocalho',940),
  ('br-mobileviagem','Móbile de viagem','Brinquedos','Prende no bebê conforto.',800,1500,'ic-mobile',950),
  ('br-musica','Caixinha de música','Brinquedos','Canção de ninar.',1500,3000,'ic-musica',960),
  ('br-tapete','Tapete de atividades','Brinquedos','Um mundinho para explorar.',2500,4500,'ic-tapete',970),
  ('br-espelho','Espelho de brincar','Brinquedos','Seguro para bebês.',800,1500,'ic-espelho',980),
  ('br-mimopais','Kit mimo dos papais','Brinquedos','Chá e docinho para Victor & Paula.',1000,2000,'ic-colonia',990)
on conflict (id) do nothing;
