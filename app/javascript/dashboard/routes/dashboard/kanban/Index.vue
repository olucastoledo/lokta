<script setup>
import { computed } from 'vue';
import { useRoute } from 'vue-router';

const route = useRoute();
const accountId = computed(() => route.params.accountId);
</script>

<template>
  <div class="flex flex-col w-full h-full bg-white dark:bg-slate-900">
    <iframe
      :src="`https://kanban.lokta.com.br?accountId=${accountId}`"
      class="flex-1 w-full h-full border-0"
      allow="clipboard-read; clipboard-write; camera; microphone; geolocation"
    />
  </div>
</template>
