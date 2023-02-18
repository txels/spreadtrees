-- truncate table entity;

insert into entity values('sarah', 'person', '{"name": "sarah", "level": 2}');
insert into entity values('anna', 'person', '{"name": "anna", "level": 2}');
insert into entity values('laura', 'person', '{"name": "laura", "level": 2}');
insert into entity values('carles', 'person', '{"name": "carles", "level": 2}');
insert into entity values('mark', 'person', '{"name": "mark", "level": 1}');
insert into entity values('meg', 'person', '{"name": "meg", "level": 1}');
insert into entity values('steph', 'person', '{"name": "steph", "level": 1}');

insert into entity values('dsg', 'team', '{"name": "design", "tier": 1}');
insert into entity values('eng', 'team', '{"name": "eng", "tier": 1}');
insert into entity values('ops', 'team', '{"name": "ops", "tier": 1}');
insert into entity values('os', 'team', '{"name": "os", "tier": 0}');
insert into entity values('pro', 'team', '{"name": "product", "tier": 1}');


-- truncate table hierarchy;

-- teams
insert into hierarchy values ('multidisc', 'os', 'pro');
insert into hierarchy values ('multidisc', 'os', 'eng');
insert into hierarchy values ('multidisc', 'os', 'ops');
insert into hierarchy values ('multidisc', 'os', 'dsg');
-- people in teams
insert into hierarchy values ('multidisc', 'os.eng', 'mark');
insert into hierarchy values ('multidisc', 'os.eng', 'anna');
insert into hierarchy values ('multidisc', 'os.eng', 'carles');
insert into hierarchy values ('multidisc', 'os.dsg', 'laura');
insert into hierarchy values ('multidisc', 'os.ops', 'sarah');
insert into hierarchy values ('multidisc', 'os.ops', 'steph');
insert into hierarchy values ('multidisc', 'os.pro', 'meg');

-- managers
insert into hierarchy values ('manager', 'mark', 'eng');
insert into hierarchy values ('manager', 'meg', 'pro');
insert into hierarchy values ('manager', 'mark', 'carles');
insert into hierarchy values ('manager', 'mark', 'anna');
insert into hierarchy values ('manager', 'meg', 'sarah');
insert into hierarchy values ('manager', 'meg', 'laura');
