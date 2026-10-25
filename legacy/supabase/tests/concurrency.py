#!/usr/bin/env python3
"""Race separate PostgreSQL sessions against CAS and publication invariants."""
import concurrent.futures
import json
import subprocess
import sys

psql, socket, port = sys.argv[1:]
base = [psql, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1', '-h', socket, '-p', port, '-d', 'postgres']
owner = '33333333-3333-3333-3333-333333333333'

def sql_literal(value):
    return "'" + str(value).replace("'", "''") + "'"

def query(sql, check=True):
    result = subprocess.run(base, input=sql, text=True, capture_output=True)
    if check and result.returncode:
        raise AssertionError(result.stderr)
    return result

def last_json(result):
    return json.loads(result.stdout.strip().splitlines()[-1])

def owner_query(sql):
    return f"begin; set local role authenticated; set local request.jwt.claim.sub='{owner}'; {sql}; commit;"

query(f"insert into auth.users(id) values('{owner}');")
created = last_json(query(owner_query("select public.recall_create_project('Race project','Client','Creative','race-create-0001')")))
project = created['project']['id']
query(owner_query(f"select public.recall_mutate_project({sql_literal(project)},1,'add_item','{{\"item\":{{\"id\":\"race-item\",\"title\":\"Original\"}}}}','race-add-0001')"))
statements = [owner_query(f"select public.recall_mutate_project({sql_literal(project)},2,'set_status','{{\"itemId\":\"race-item\",\"status\":\"{status}\"}}','race-status-{index:04}')") for index, status in enumerate(('inProgress', 'delivered'))]
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda statement: query(statement, check=False), statements))
assert sum(result.returncode == 0 for result in results) == 1, 'Exactly one concurrent CAS write must commit.'
assert any('The project changed.' in result.stderr for result in results if result.returncode), 'CAS loser must report a stale version.'
print('PASS: separate concurrent owner sessions commit exactly one CAS mutation')

links = []
revisions = []
for index, title in enumerate(('Proposal A', 'Proposal B')):
    payload = {'items': [{'id': 'race-item', 'title': title}], 'evidence': [{'id': f'race-source-{index}', 'text': title, 'language': 'en', 'kind': 'originalText'}]}
    envelope = last_json(query(owner_query(f"select public.recall_mutate_project({sql_literal(project)},{3 + index},'propose_change',{sql_literal(json.dumps(payload))}::jsonb,'race-proposal-{index:04}')")))
    revision = envelope['project']['proposals'][-1]['id']
    revisions.append(revision)
    links.append(last_json(query(owner_query(f"select public.recall_create_review_link({sql_literal(project)},{sql_literal(revision)},'client')"))))
statements = [f"begin; set local role anon; select public.recall_respond_review({sql_literal(link['token'])},'confirm','','race-response-{index:04}'); commit;" for index, link in enumerate(links)]
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda statement: query(statement, check=False), statements))
assert sum(result.returncode == 0 for result in results) == 1, 'Exactly one competing revision may publish.'
assert any('closed or stale' in result.stderr for result in results if result.returncode), 'Competing publication loser must be stale.'
current = last_json(query(owner_query('select public.recall_list_projects()')))[0]
assert current['version'] == 6, 'A rejected race must not increment the project version.'
assert current['project']['currentRevision']['id'] in revisions
assert current['project']['currentRevision']['acceptedBy'] == ['you', 'client']
print('PASS: separate concurrent review sessions publish exactly one competing immutable proposal')

# Race two creations when one Free project slot remains.
query(owner_query("select public.recall_create_project('Second race project','Client','Creative','race-second-project')"))
statements = [owner_query(f"select public.recall_create_project('Concurrent project {index}','Client','Creative','race-cap-project-{index:04}')") for index in range(2)]
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda statement: query(statement, check=False), statements))
assert sum(result.returncode == 0 for result in results) == 1, 'Exactly one remaining Free project slot may be allocated.'
assert any('project limit' in result.stderr for result in results if result.returncode)
assert len(last_json(query(owner_query('select public.recall_list_projects()')))) == 3
print('PASS: concurrent creations cannot exceed the Free three-project cap')

# Reserve the last Free per-user slot from two independent service sessions.
query(f"insert into recall_private.analysis_usage(owner_id,usage_day,request_count) values('{owner}',(now() at time zone 'UTC')::date,4); insert into recall_private.analysis_service_usage(usage_day,request_count) values((now() at time zone 'UTC')::date,0);")
statement = f"begin; set local role service_role; select public.recall_reserve_analysis('{owner}',100); commit;"
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(lambda unused: query(statement), range(2)))
assert sorted(result.stdout.strip() for result in results) == ['f', 't']
counts = last_json(query(f"select json_build_object('user',(select request_count from recall_private.analysis_usage where owner_id='{owner}'),'service',(select request_count from recall_private.analysis_service_usage));"))
assert counts == {'user': 5, 'service': 1}, 'Rejected user reservation must not consume aggregate budget.'
print('PASS: concurrent quota reservations enforce the Free daily five-request cap atomically')

# Different accounts compete for the last shared service budget slot.
fanout = ['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb']
query("insert into auth.users(id) values('" + fanout[0] + "'),('" + fanout[1] + "'); update recall_private.analysis_service_usage set request_count=99;")
statements = [f"begin; set local role service_role; select public.recall_reserve_analysis('{uid}',100); commit;" for uid in fanout]
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(query, statements))
assert sorted(result.stdout.strip() for result in results) == ['f', 't']
counts = last_json(query("select json_build_object('users',(select coalesce(sum(request_count),0) from recall_private.analysis_usage where owner_id in ('" + fanout[0] + "','" + fanout[1] + "')),'service',(select request_count from recall_private.analysis_service_usage));"))
assert counts == {'users': 1, 'service': 100}, 'Global and per-user reservations must commit together.'
print('PASS: concurrent account fanout cannot exceed the combined UTC-day budget of 100')
