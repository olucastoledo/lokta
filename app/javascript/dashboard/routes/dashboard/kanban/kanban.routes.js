import { frontendURL } from '../../../helper/URLHelper';
import KanbanIndex from './Index.vue';

export default [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    name: 'kanban_view',
    component: KanbanIndex,
    meta: {
      permissions: ['administrator', 'agent', 'custom_role'],
    },
  },
];
