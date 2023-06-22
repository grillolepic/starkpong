<script setup>
import { ref, onMounted } from 'vue';
import { RouterLink } from 'vue-router';
import { useStarknetStore } from '../stores/starknet';
import { useGameRoomFactoryStore } from '../stores/game_room_factory';
import TransactionStatus from '../components/TransactionStatus.vue';
import TokenInput from '../components/TokenInput.vue';

const starknetStore = useStarknetStore();
const gameRoomFactoryStore = useGameRoomFactoryStore();

onMounted(() => {
    gameRoomFactoryStore.updateGameRoom();
});

</script>

<template>
  <div class="flex column flex-center max-height-without-navbar">
    <div class="flex column flex-center">
      <div class="logo">Create Room</div>
      <div id="createRoomContents" class="flex column flex-center" v-if="starknetStore.transaction.status == null && !gameRoomFactoryStore.loadingGameRoom">
        <TokenInput class="tokenInput" ref="tokenInput" />
        <div class="button big-button" @click="create()" v-if="starknetStore.transaction.status == null">
          CREATE GAME ROOM</div>
        <RouterLink to="/" v-if="starknetStore.transaction.status == null">
          <div class="button big-button">BACK TO HOME</div>
        </RouterLink>
      </div>
      <div v-else-if="gameRoomFactoryStore.loadingGameRoom" class="inline-spinner"></div>
      <TransactionStatus v-else />
    </div>
  </div>
</template>

<script>
  let tokenInput = ref(null);
  function create() {
    useGameRoomFactoryStore().createRoom(tokenInput.value.tokenAmount);
  }
</script>

<style scoped>
#createRoomContents {
  justify-content: flex-start;
  height: 250px;
  width: 450px;
}

.logo {
  font-size: 65px;
  line-height: 65px;
}

.info {
  margin-top: 15px;
  text-align: center;
}

.backToHome {
  color: white !important;
  text-decoration: underline;
}

.inline-spinner {
  margin-top: 25px;
}

.tokenInput {
  margin: 15px 0px;
}
</style>