<script setup>
import { useStarknetStore } from '@/stores/starknet';
import { computed } from 'vue';

const starknetStore = useStarknetStore();

const btnConnectText = computed(() => {
  if (starknetStore.connected && starknetStore.address) {
    if (starknetStore.networkOk) {
      if (starknetStore.starkName == null) {
        return starknetStore.shortAddress(12);
      } else {
        return starknetStore.starkName;
      }
    } else {
      return 'UNSUPPORTED NETWORK';
    }
  } else {
    return 'CONNECT';
  }
});

function toggleConnect(event) {
  if (starknetStore.connected && starknetStore.address) {
    if (starknetStore.networkOk) {
      starknetStore.logout();
    }
  } else {
    starknetStore.connectStarknet();
  }
}
</script>

<template>
  <div id="ConnectButton" class="button noSelect" :class="{
    'connected-button':
      starknetStore.connected && starknetStore.address && starknetStore.networkOk
  }" @click="toggleConnect">
    <span>{{ btnConnectText }}</span>
  </div>
</template>

<style scoped>
.connected-button:hover span {
  display: none;
}

.connected-button:hover:before {
  content: 'DISCONNECT';
}
</style>