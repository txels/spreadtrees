truncate table entity cascade;
\copy entity from 'entities.csv'
\copy hierarchy from 'hierarchies.csv'

insert into catalog(name, value, data) values
    ('seniority', 'Senior', '{"score": 3}'),
    ('seniority', 'Junior', '{"score": 1}')
;
