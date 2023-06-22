import { createRouter, createWebHistory } from 'vue-router';
import HomeView from '../views/HomeView.vue';

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: HomeView
    },
    {
      path: '/faucet',
      name: 'Faucet',
      component: () => import('../views/Faucet.vue'),
    },
    {
      path: '/create',
      name: 'CreateRoom',
      component: () => import('../views/CreateRoom.vue'),
    },
    {
      path: '/join',
      name: 'JoinRoom',
      component: () => import('../views/JoinRoom.vue'),
    },
    {
      path: '/room/:id',
      name: 'GameRoom',
      component: () => import('../views/GameRoom.vue'),
      props: true
    },
    {
      path: '/game',
      name: 'Game',
      component: () => import('../views/Game.vue')
    },
    {
      path: '/:pathMatch(.*)*',
      name: 'NotFound',
      component: () => import('../views/NotFound.vue'),
    }
  ]
});

export default router;
