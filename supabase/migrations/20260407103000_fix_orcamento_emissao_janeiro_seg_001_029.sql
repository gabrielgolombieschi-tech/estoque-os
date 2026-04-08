begin;

update m.orcamento
   set emissao_date = date '2026-01-29',
       updated_at = now()
 where tenant_id = '3ced7cfa-efbb-4f0f-addc-2028f60d1ca7'::uuid
   and empresa_id = 'f0e74f49-a127-46b4-901b-f7b37e43c690'::uuid
   and deleted_at is null
   and codigo in (
     'SEG-001-026',
     'SEG-002-026',
     'SEG-003-026',
     'SEG-004-026',
     'SEG-005-026',
     'SEG-006-026',
     'SEG-007-026',
     'SEG-008-026',
     'SEG-009-026',
     'SEG-010-026',
     'SEG-011-026',
     'SEG-012-026',
     'SEG-013-026',
     'SEG-014-026',
     'SEG-015-026',
     'SEG-016-026',
     'SEG-017-026',
     'SEG-018-026',
     'SEG-019-026',
     'SEG-020-026',
     'SEG-021-026',
     'SEG-022-026',
     'SEG-023-026',
     'SEG-024-026',
     'SEG-025-026',
     'SEG-026-026',
     'SEG-027-026',
     'SEG-028-026',
     'SEG-029-026'
   );

commit;
