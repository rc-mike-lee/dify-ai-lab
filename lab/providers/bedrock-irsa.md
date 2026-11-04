# Bedrock without keys: IAM role for lab-litellm (EKS IRSA)

1. In the AWS account that owns the cluster, enable the model under **Bedrock → Model access**
   in your chosen region.
2. Create an IAM role trusted by the cluster's OIDC provider for the ServiceAccount
   `dify-lab/lab-litellm`, with the policy in `bedrock-iam-policy.json` (fill in the model or
   inference-profile ID and account). With eksctl:

   ```bash
   eksctl create iamserviceaccount --cluster <cluster> --namespace dify-lab --name lab-litellm \
     --role-name dify-lab-bedrock --attach-policy-arn <policy-arn> --approve --override-existing-serviceaccounts
   ```

   Or annotate the existing ServiceAccount with a role you created:

   ```bash
   kubectl annotate sa lab-litellm -n dify-lab eks.amazonaws.com/role-arn=arn:aws:iam::<account-id>:role/dify-lab-bedrock
   kubectl rollout restart deploy/lab-litellm -n dify-lab
   ```

3. Set `aws_region_name` in `bedrock-claude.yaml` / `bedrock-openai.yaml` to the region where
   you enabled the model.

If calls fail with no AWS credentials found, check that the pod has the
`AWS_WEB_IDENTITY_TOKEN_FILE` environment variable (`kubectl describe pod`); if not, the IRSA
webhook didn't apply. Re-check the annotation and restart the deployment.
