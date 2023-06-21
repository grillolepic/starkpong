<script setup>
import { ref, onMounted } from 'vue';
import { RouterLink, useRouter } from 'vue-router';
import { useStarknetStore } from '../stores/starknet';
import { useGameTokenStore } from '../stores/game_token';
import TransactionStatus from '../components/TransactionStatus.vue';
import TokenInput from '../components/TokenInput.vue';

const starknetStore = useStarknetStore();
const gameTokenStore = useGameTokenStore();
const router = useRouter();

let wager = ref(0);

onMounted(async () => {
  //router.push('/');
});
</script>

<template>
  <div class="flex column flex-center max-height-without-navbar">
    <div id="MainMenu" class="flex column flex-center">
      <div class="logo">Create Room</div>
      <div id="createRoomContents" class="flex column flex-center" v-if="starknetStore.transaction.status == null">
        <TokenInput class="tokenInput" ref="wager" />
        <div class="button" @click="gameTokenStore.claim()" v-if="starknetStore.transaction.status == null">
          CREATE GAME ROOM</div>
        <RouterLink to="/" v-if="starknetStore.transaction.status == null">
          <div class="info backToHome">Back to Home</div>
        </RouterLink>
      </div>
      <TransactionStatus v-else />
    </div>
  </div>
</template>

<style scoped>
#createRoomContents {
  justify-content: flex-start;
  height: 200px;
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

.button {
  margin-top: 25px;
  width: 450px;
}

.inline-spinner {
  margin-top: 25px;
}

.tokenInput {
  margin-top: 25px;
}
</style>