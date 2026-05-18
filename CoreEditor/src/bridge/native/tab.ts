import { NativeModule } from '../nativeModule';

/**
 * @shouldExport true
 * @invokePath tab
 * @bridgeName NativeBridgeTab
 */
export interface NativeModuleTab extends NativeModule {
  selectTab({ index }: { index: CodeGen_Int }): void;
}
