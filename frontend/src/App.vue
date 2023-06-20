<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { RouterView } from 'vue-router';
import NavBar from '@/components/NavBar.vue';
import Footer from '@/components/Footer.vue';
import { useStarknetStore } from './stores/starknet';

const starknetStore = useStarknetStore();

const width = ref(window.innerWidth);
const handleResize = () => {
    width.value = window.innerWidth;
};
onMounted(() => { window.addEventListener('resize', handleResize); });
onUnmounted(() => { window.removeEventListener('resize', handleResize); });

const isMobile = computed(() => width.value < 700);
</script>

<template>
  <div v-if="isMobile" class="flex column flex-center max-height">
    <div class="logo">StarkPong</div>
    <div class="info">Tha app is currently only available on desktop</div>
  </div>
  <div class="max-width flex column align-items-center" v-else>
    <NavBar class="max-width" />
    <RouterView v-if="starknetStore.isStarknetReady"/>
    <div v-else class="flex column flex-center max-height-without-navbar">
      <div class="info" v-if="!starknetStore.connected">Connect to StarkNet to begin</div>
      <div class="info" v-else>Switch to StarkNet Goerli Testnet to begin</div>
    </div>
    <Footer />
  </div>
</template>

<style scoped>
.logo {
  font-size: 50px;
}
.info {
  font-size: 16px;
  letter-spacing: 2px;
}

</style>