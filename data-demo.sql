truncate table entity;

-- people
insert into entity values('bob', 'person', 'name => bob, level => 1');
insert into entity values('jan', 'person', 'name => jan, level => 2');
insert into entity values('joe', 'person', 'name => joe, level => 2');
-- teams
insert into entity values('dev', 'team', 'name => dev, tier => 2, cost=>12');
insert into entity values('design', 'team', 'name => design, tier => 2, cost=>23');
insert into entity values('product', 'team', 'name => product, tier => 1');
insert into entity values('other', 'team', 'name => other, tier => 1');
insert into entity values('org', 'team', 'name => org, tier => 0');
-- ownership areas
insert into entity values('ux', 'ownership', 'name => "UX"');
insert into entity values('use', 'ownership', 'name => "Usability"');
insert into entity values('acc', 'ownership', 'name => "Accessibility"');
insert into entity values('sfw', 'ownership', 'name => "Software Engineering"');
insert into entity values('dx', 'ownership', 'name => "Developer Experience"');
insert into entity values('api', 'ownership', 'name => "API design"');
insert into entity values('pla', 'ownership', 'name => "Platform"');
insert into entity values('del', 'ownership', 'name => "Continuous Delivery"');


truncate table hierarchy;

-- multidisc hierarchy
-- teams
insert into hierarchy values ('multidisc', 'org', 'product');
insert into hierarchy values ('multidisc', 'org', 'other');
insert into hierarchy values ('multidisc', 'org.product', 'design');
insert into hierarchy values ('multidisc', 'org.product', 'dev');
-- people in teams
insert into hierarchy values ('multidisc', 'org.product.dev', 'jan');
insert into hierarchy values ('multidisc', 'org.product.dev', 'bob');
insert into hierarchy values ('multidisc', 'org.product.design', 'bob');
insert into hierarchy values ('multidisc', 'org.product.design', 'joe');
-- team and people ownership areas
insert into hierarchy values ('multidisc', 'org.product.design', 'acc');
insert into hierarchy values ('multidisc', 'org.product.design', 'use');
insert into hierarchy values ('multidisc', 'bob', 'acc');
insert into hierarchy values ('multidisc', 'jan', 'use');

-- other hierarchies
-- managers (for people and teams)
insert into hierarchy values ('manager', 'bob', 'jan');
insert into hierarchy values ('manager', 'bob', 'joe');
insert into hierarchy values ('manager', 'bob', 'product');

-- ownership areas: categorization
insert into hierarchy values ('ownership', 'ux', 'use');
insert into hierarchy values ('ownership', 'ux', 'acc');
insert into hierarchy values ('ownership', 'sfw', 'dx');
insert into hierarchy values ('ownership', 'sfw.dx', 'pla');
insert into hierarchy values ('ownership', 'sfw.dx', 'del');
insert into hierarchy values ('ownership', 'sfw', 'api');
